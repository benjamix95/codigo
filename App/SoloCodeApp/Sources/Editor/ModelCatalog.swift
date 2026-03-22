import Foundation

// MARK: - Provider Model Lists

let openAIModels = [
    "gpt-5.3-codex", "gpt-5.2-instant", "gpt-5.2-thinking",
    "o3", "o3-pro", "o4-mini",
    "gpt-4o", "gpt-4o-mini", "gpt-4.5",
]

let anthropicModels = [
    "claude-opus-4-6", "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
    "claude-opus-4", "claude-sonnet-4",
]

let googleModels = [
    "gemini-3-pro", "gemini-3-flash-preview",
    "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
]

let minimaxModels = [
    "MiniMax-M2.5", "MiniMax-M2.1", "MiniMax-M2.1-lightning", "MiniMax-M2",
]

let grokModels = [
    "grok-4-1-fast-reasoning", "grok-4-1-fast-non-reasoning",
    "grok-code-fast-1",
    "grok-4-0709",
    "grok-3", "grok-3-mini",
]

let kiloModels = [
    "kilo/giga-potato-thinking",
    "kilo/giga-potato",
    "kilo/corethink:free",
    "kilo/kilo-auto/free",
    "kilo/kilo/auto-free",
    "kilo/x-ai/grok-code-fast-1:optimized:free",
    "kilo/minimax/minimax-m2.5:free",
    "kilo/nvidia/nemotron-3-super-120b-a12b:free",
    "kilo/arcee-ai/trinity-large-preview:free",
    "kilo/stepfun/step-3.5-flash:free",
    "kilo/xiaomi/mimo-v2-pro:free",
    "kilo/xiaomi/mimo-v2-omni:free",
    "kilo/openrouter/free",
]

// MARK: - OpenRouter

func normalizeOpenRouterModelId(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "anthropic/claude-sonnet-4-6" }
    switch trimmed {
    case "qwen/qwen3-next-80b:free":
        return "deepseek/deepseek-r1-0528:free"
    default:
        return trimmed
    }
}

let openRouterPopularModels = [
    "anthropic/claude-opus-4-6", "anthropic/claude-sonnet-4-6",
    "google/gemini-3-pro", "google/gemini-2.5-pro",
    "openai/gpt-5.3-codex", "openai/o3",
    "deepseek/deepseek-r1",
    "meta-llama/llama-4-maverick",
    "qwen/qwen3-coder-480b-a35b",
    "minimax/minimax-m2.5",
    "x-ai/grok-4-1-fast-reasoning",
]

let openRouterFreeModels = [
    "arcee-ai/trinity-large-preview:free",
    "arcee-ai/trinity-mini:free",
    "cognitivecomputations/dolphin-mistral-24b-venice-edition:free",
    "google/gemma-3-12b-it:free",
    "google/gemma-3-27b-it:free",
    "google/gemma-3-4b-it:free",
    "google/gemma-3n-e2b-it:free",
    "google/gemma-3n-e4b-it:free",
    "liquid/lfm-2.5-1.2b-instruct:free",
    "liquid/lfm-2.5-1.2b-thinking:free",
    "meta-llama/llama-3.2-3b-instruct:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "mistralai/mistral-small-3.1-24b-instruct:free",
    "nousresearch/hermes-3-llama-3.1-405b:free",
    "nvidia/nemotron-3-nano-30b-a3b:free",
    "nvidia/nemotron-nano-12b-v2-vl:free",
    "nvidia/nemotron-nano-9b-v2:free",
    "openai/gpt-oss-120b:free",
    "openai/gpt-oss-20b:free",
    "openrouter/free",
    "qwen/qwen3-235b-a22b-thinking-2507",
    "qwen/qwen3-4b:free",
    "qwen/qwen3-coder:free",
    "qwen/qwen3-next-80b-a3b-instruct:free",
    "qwen/qwen3-vl-235b-a22b-thinking",
    "qwen/qwen3-vl-30b-a3b-thinking",
    "stepfun/step-3.5-flash:free",
    "z-ai/glm-4.5-air:free",
]
