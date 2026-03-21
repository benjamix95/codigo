import Foundation

/// Prezzi per modello (USD per 1M token) - stima costi API
public enum ModelPricing {
    public static func estimatedCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        let (inPrice, outPrice) = pricePerMillion(for: model)
        let inCost = Double(inputTokens) / 1_000_000 * inPrice
        let outCost = Double(outputTokens) / 1_000_000 * outPrice
        return inCost + outCost
    }

    public static func contextWindowSize(for model: String) -> Int {
        let normalized = model.lowercased()
        if normalized.contains("gpt-4o") || normalized.contains("gpt-4-turbo") { return 128_000 }
        if normalized.contains("gpt-4") { return 128_000 }
        if normalized.contains("gpt-3.5") { return 16_000 }
        if normalized.contains("o1") || normalized.contains("o3") || normalized.contains("o4") { return 128_000 }
        if normalized.contains("claude-3-5-sonnet") || normalized.contains("claude-3-5-haiku") { return 200_000 }
        if normalized.contains("claude-3-opus") || normalized.contains("claude-3-sonnet") { return 200_000 }
        if normalized.contains("claude-3") { return 200_000 }
        return 128_000
    }

    private static func pricePerMillion(for model: String) -> (input: Double, output: Double) {
        let m = model.lowercased()
        switch m {
        case _ where m.contains("gpt-4o-mini"):
            return (0.15, 0.60)
        case _ where m.contains("gpt-4o"):
            return (5.00, 15.00)
        case _ where m.contains("gpt-4-turbo"):
            return (10.00, 30.00)
        case _ where m.contains("gpt-4"):
            return (30.00, 60.00)
        case _ where m.contains("gpt-3.5-turbo"):
            return (0.50, 1.50)
        case _ where m.contains("o1") || m.contains("o3") || m.contains("o4"):
            return (15.00, 60.00)
        case _ where m.contains("claude-3-5-sonnet"):
            return (3.00, 15.00)
        case _ where m.contains("claude-3-5-haiku"):
            return (0.80, 4.00)
        case _ where m.contains("claude-3-opus"):
            return (15.00, 75.00)
        case _ where m.contains("claude-3-sonnet"):
            return (3.00, 15.00)
        case _ where m.contains("claude-3-haiku"):
            return (0.25, 1.25)
        case _ where m.contains("claude-sonnet"):
            return (3.00, 15.00)
        default:
            return (1.00, 3.00)
        }
    }
}
