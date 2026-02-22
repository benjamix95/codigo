import Foundation

func normalizeOpenRouterModelId(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "anthropic/claude-sonnet-4-6" }
    switch trimmed {
    case "qwen/qwen3-next-80b:free":
        // Modello deprecato/non valido su OpenRouter.
        return "deepseek/deepseek-r1-0528:free"
    default:
        return trimmed
    }
}

let openRouterPopularModels = [
    "anthropic/claude-opus-4-6", "anthropic/claude-sonnet-4-6",
    "google/gemini-3-pro", "google/gemini-2.5-pro",
    "minimax/minimax-m2.5",
    "z-ai/glm-5",
    "qwen/qwen3.5-plus-2025-01-25", "qwen/qwen3-coder-480b-a35b",
    "meta-llama/llama-4-maverick",
    "deepseek/deepseek-r1",
]

let openRouterFreeModels = [
    "arcee-ai/trinity-large-preview:free",
    "arcee-ai/trinity-mini:free",
    "cognitivecomputations/dolphin-mistral-24b-venice-edition:free",
    "z-ai/glm-4.5-air:free",
    "deepseek/deepseek-r1-0528:free",
    "google/gemma-3-12b-it:free",
    "google/gemma-3-4b-it:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "google/gemma-3n-e2b-it:free",
    "google/gemma-3n-e4b-it:free",
    "google/gemma-3-27b-it:free",
    "liquid/lfm-2.5-1.2b-instruct:free",
    "liquid/lfm-2.5-1.2b-thinking:free",
    "meta-llama/llama-3.2-3b-instruct:free",
    "mistralai/mistral-small-3.1-24b-instruct:free",
    "nousresearch/hermes-3-llama-3.1-405b:free",
    "nvidia/nemotron-3-nano-30b-a3b:free",
    "nvidia/nemotron-nano-12b-v2-vl:free",
    "nvidia/nemotron-nano-9b-v2:free",
    "openai/gpt-oss-120b:free",
    "openai/gpt-oss-20b:free",
    "qwen/qwen3-4b:free",
    "qwen/qwen3-coder:free",
    "qwen/qwen3-next-80b-a3b-instruct:free",
    "stepfun/step-3.5-flash:free",
    "upstage/solar-pro-3:free",
]
