import CoreML
import Foundation

// MARK: - CoreMLEmbeddingBackend

/// Generates 384-dim sentence embeddings using a local CoreML model
/// (all-MiniLM-L6-v2 converted to `.mlmodelc`).
///
/// The model is loaded lazily on first call and kept in memory.
/// Inference runs on the ANE / GPU via CoreML, falling back to CPU.
public actor CoreMLEmbeddingBackend {

    /// Embedding dimensionality produced by all-MiniLM-L6-v2.
    public static let embeddingDim = 384

    private var model: MLModel?
    private let tokenizer: WordPieceTokenizer
    private var loadError: Error?

    // MARK: - Init

    public init(tokenizer: WordPieceTokenizer) {
        self.tokenizer = tokenizer
    }

    // MARK: - Public API

    /// Embed a single text string → 384-dim Float array.
    /// Returns `nil` if the model fails to load.
    public func embed(_ text: String) -> [Float]? {
        guard let model = loadModelIfNeeded() else { return nil }
        let input = tokenizer.encode(text)
        return infer(model: model, input: input)
    }

    /// Embed a batch of texts. Returns one vector per input (same order).
    /// Texts that fail produce a zero vector.
    public func embedBatch(_ texts: [String]) -> [[Float]] {
        guard let model = loadModelIfNeeded() else {
            return texts.map { _ in [Float](repeating: 0, count: Self.embeddingDim) }
        }
        return texts.map { text in
            let input = tokenizer.encode(text)
            return infer(model: model, input: input)
                ?? [Float](repeating: 0, count: Self.embeddingDim)
        }
    }

    /// Whether the CoreML model is available on this machine.
    public var isAvailable: Bool {
        loadModelIfNeeded() != nil
    }

    // MARK: - Model Loading

    @discardableResult
    private func loadModelIfNeeded() -> MLModel? {
        if let model { return model }
        if loadError != nil { return nil }

        do {
            let modelURL = try findModelURL()
            let config = MLModelConfiguration()
            config.computeUnits = .all // prefer ANE, fall back GPU/CPU
            let loaded = try MLModel(contentsOf: modelURL, configuration: config)
            self.model = loaded
            return loaded
        } catch {
            self.loadError = error
            return nil
        }
    }

    private func findModelURL() throws -> URL {
        // Look in the main bundle first (app context).
        if let url = Bundle.main.url(forResource: "all-MiniLM-L6-v2", withExtension: "mlmodelc") {
            return url
        }
        // Fallback: sibling of the executable.
        let execDir = Bundle.main.bundleURL
            .deletingLastPathComponent()
        let fallback = execDir
            .appendingPathComponent("Models")
            .appendingPathComponent("all-MiniLM-L6-v2.mlmodelc")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        throw CoreMLEmbeddingError.modelNotFound
    }

    // MARK: - Inference

    private func infer(model: MLModel, input: TokenizedInput) -> [Float]? {
        do {
            let provider = try BERTInputProvider(input: input, seqLength: tokenizer.maxLength)
            let prediction = try model.prediction(from: provider)
            return extractEmbedding(from: prediction)
        } catch {
            return nil
        }
    }

    /// Extract the 384-dim embedding from the model output.
    /// Applies mean pooling over non-pad tokens.
    private func extractEmbedding(from output: MLFeatureProvider) -> [Float]? {
        // Try common output names used by MiniLM CoreML exports.
        let candidateNames = ["output", "last_hidden_state", "sentence_embedding", "embeddings"]
        for name in candidateNames {
            guard let feature = output.featureValue(for: name),
                  let multiArray = feature.multiArrayValue else { continue }

            let shape = multiArray.shape.map { $0.intValue }
            // Shape: [1, seqLen, 384] → mean-pool over seqLen.
            if shape.count == 3, shape[2] == Self.embeddingDim {
                return meanPool(multiArray, seqLen: shape[1], dim: shape[2])
            }
            // Shape: [1, 384] → already pooled.
            if shape.count == 2, shape[1] == Self.embeddingDim {
                return extractFlat(multiArray, count: Self.embeddingDim)
            }
        }
        return nil
    }

    private func meanPool(_ array: MLMultiArray, seqLen: Int, dim: Int) -> [Float] {
        var result = [Float](repeating: 0, count: dim)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: seqLen * dim)
        for t in 0..<seqLen {
            for d in 0..<dim {
                result[d] += ptr[t * dim + d]
            }
        }
        let scale = 1.0 / Float(seqLen)
        for d in 0..<dim { result[d] *= scale }
        return l2Normalize(result)
    }

    private func extractFlat(_ array: MLMultiArray, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count { result[i] = ptr[i] }
        return l2Normalize(result)
    }

    /// L2-normalize so cosine similarity = dot product.
    private func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-12 else { return v }
        return v.map { $0 / norm }
    }
}

// MARK: - BERTInputProvider

/// Wraps tokenized input as an MLFeatureProvider for CoreML prediction.
private final class BERTInputProvider: MLFeatureProvider {
    let featureNames: Set<String>
    private let inputIdsArray: MLMultiArray
    private let attentionMaskArray: MLMultiArray

    init(input: TokenizedInput, seqLength: Int) throws {
        let shape = [1, NSNumber(value: seqLength)]
        self.inputIdsArray = try MLMultiArray(shape: shape, dataType: .int32)
        self.attentionMaskArray = try MLMultiArray(shape: shape, dataType: .int32)

        for i in 0..<seqLength {
            inputIdsArray[i] = NSNumber(value: input.inputIds[i])
            attentionMaskArray[i] = NSNumber(value: input.attentionMask[i])
        }
        self.featureNames = Set(["input_ids", "attention_mask"])
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "input_ids": return MLFeatureValue(multiArray: inputIdsArray)
        case "attention_mask": return MLFeatureValue(multiArray: attentionMaskArray)
        default: return nil
        }
    }
}

// MARK: - Errors

public enum CoreMLEmbeddingError: Error, LocalizedError {
    case modelNotFound

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "CoreML model all-MiniLM-L6-v2.mlmodelc not found in bundle or Models directory."
        }
    }
}
