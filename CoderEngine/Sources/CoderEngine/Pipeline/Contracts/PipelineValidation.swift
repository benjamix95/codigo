import Foundation

// MARK: - PipelineValidatable

/// Protocollo per validazione strutturale dei contratti pipeline.
/// Ogni contratto MUST implementare `validate()` che lancia
/// `PipelineValidationError` se i vincoli non sono rispettati.
public protocol PipelineValidatable {
    func validate() throws
}

// MARK: - PipelineValidationError

/// Errori di validazione per i contratti della pipeline.
public enum PipelineValidationError: Error, Sendable, Equatable {
    case missingRequiredField(field: String, contract: String)
    case valueOutOfRange(field: String, contract: String, value: String, range: String)
    case invalidEnumValue(field: String, contract: String, value: String)
    case invalidTransition(from: String, to: String, contract: String)
    case constraintViolation(field: String, contract: String, reason: String)
}

extension PipelineValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingRequiredField(field, contract):
            "[\(contract)] Campo obbligatorio mancante: '\(field)'"
        case let .valueOutOfRange(field, contract, value, range):
            "[\(contract)] '\(field)' = \(value) fuori range \(range)"
        case let .invalidEnumValue(field, contract, value):
            "[\(contract)] Valore enum invalido per '\(field)': '\(value)'"
        case let .invalidTransition(from, to, contract):
            "[\(contract)] Transizione non valida: \(from) → \(to)"
        case let .constraintViolation(field, contract, reason):
            "[\(contract)] Vincolo violato su '\(field)': \(reason)"
        }
    }
}

// MARK: - Validation Helpers

/// Utility di validazione riutilizzabili nei contratti.
public enum PipelineValidationHelpers {

    /// Valida che una stringa non sia vuota.
    public static func requireNonEmpty(
        _ value: String,
        field: String,
        contract: String
    ) throws {
        guard !value.isEmpty else {
            throw PipelineValidationError.missingRequiredField(
                field: field, contract: contract
            )
        }
    }

    /// Valida un intero in un range chiuso.
    public static func requireRange<T: Comparable & CustomStringConvertible>(
        _ value: T,
        range: ClosedRange<T>,
        field: String,
        contract: String
    ) throws {
        guard range.contains(value) else {
            throw PipelineValidationError.valueOutOfRange(
                field: field,
                contract: contract,
                value: String(describing: value),
                range: "\(range.lowerBound)...\(range.upperBound)"
            )
        }
    }

    /// Valida un Double in un range chiuso.
    public static func requireDoubleRange(
        _ value: Double,
        range: ClosedRange<Double>,
        field: String,
        contract: String
    ) throws {
        guard range.contains(value) else {
            throw PipelineValidationError.valueOutOfRange(
                field: field,
                contract: contract,
                value: String(format: "%.4f", value),
                range: "\(range.lowerBound)...\(range.upperBound)"
            )
        }
    }

    /// Valida che un array non sia vuoto.
    public static func requireNonEmptyArray<T>(
        _ value: [T],
        field: String,
        contract: String
    ) throws {
        guard !value.isEmpty else {
            throw PipelineValidationError.missingRequiredField(
                field: field, contract: contract
            )
        }
    }

    /// Valida che un valore opzionale non sia nil.
    public static func requirePresent<T>(
        _ value: T?,
        field: String,
        contract: String
    ) throws {
        guard value != nil else {
            throw PipelineValidationError.missingRequiredField(
                field: field, contract: contract
            )
        }
    }
}
