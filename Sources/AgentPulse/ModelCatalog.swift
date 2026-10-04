import Foundation

/// Vendor behind a model. Used to group the catalog in the dashboard.
enum ModelVendor: String, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Google"
    case xai = "xAI"
    case other = "Other"

    var id: String { rawValue }
}

/// A currently available text / coding model and its published API rate.
/// Prices are USD per 1M tokens at the short-context tier, as of September 2026.
struct LLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    let vendor: ModelVendor
    let agents: [AgentType]
    let tier: String
    /// Input price, USD per 1M tokens.
    let inputUSD: Double
    /// Output price, USD per 1M tokens.
    let outputUSD: Double
    let sortIndex: Int

    var priceLabel: String {
        guard inputUSD > 0 || outputUSD > 0 else { return "" }
        return "\(USDRate.format(inputUSD)) / \(USDRate.format(outputUSD))"
    }
}

enum USDRate {
    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return "$\(Int(value.rounded()))"
        }
        return String(format: "$%.2f", value)
    }
}

enum TokenFormat {
    static func string(for tokens: Int) -> String {
        guard tokens > 0 else { return "—" }
        let value = Double(tokens)
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(tokens)"
    }
}

/// Blended estimate: coding sessions are mostly input, with a smaller output share.
enum CostEstimate {
    static func dollars(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, model: LLMModel) -> Double {
        guard model.inputUSD > 0 || model.outputUSD > 0 else { return 0 }
        let million = 1_000_000.0
        return Double(input) / million * model.inputUSD
            + Double(output) / million * model.outputUSD
            + Double(cacheRead) / million * model.inputUSD * 0.1
            + Double(cacheWrite) / million * model.inputUSD * 1.25
    }

    static func dollars(tokens: Int, model: LLMModel) -> Double {
        guard tokens > 0 else { return 0 }
        let blended = model.inputUSD * 0.75 + model.outputUSD * 0.25
        return Double(tokens) / 1_000_000 * blended
    }

    static func label(tokens: Int, model: LLMModel) -> String {
        let amount = dollars(tokens: tokens, model: model)
        guard amount > 0 else { return "" }
        if amount >= 100 {
            return "~\(grouped(amount, decimals: 0))"
        }
        return "~\(grouped(amount, decimals: 2))"
    }

    static func summary(_ amount: Double) -> String {
        if amount >= 100 {
            return grouped(amount, decimals: 0)
        }
        return grouped(amount, decimals: 2)
    }

    private static func grouped(_ amount: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let body = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(decimals)f", amount)
        return "$\(body)"
    }
}

enum LLMCatalog {
    /// Current models coding agents can actually call.
    /// Image, speech, and live-translate endpoints are omitted.
    static let all: [LLMModel] = [
        // Anthropic — Claude 5.5 family, then models still served.
        LLMModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", vendor: .anthropic, agents: [.claude, .copilot], tier: "Balanced", inputUSD: 2, outputUSD: 10, sortIndex: 0),
        LLMModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", vendor: .anthropic, agents: [.claude, .copilot], tier: "Frontier", inputUSD: 4, outputUSD: 20, sortIndex: 1),
        LLMModel(id: "claude-fable-5-1", name: "Claude Fable 5.1", vendor: .anthropic, agents: [.claude], tier: "Frontier", inputUSD: 10, outputUSD: 50, sortIndex: 2),
        LLMModel(id: "claude-opus-5", name: "Claude Opus 5", vendor: .anthropic, agents: [.claude], tier: "Frontier", inputUSD: 5, outputUSD: 25, sortIndex: 3),
        LLMModel(id: "claude-sonnet-5", name: "Claude Sonnet 5", vendor: .anthropic, agents: [.claude], tier: "Balanced", inputUSD: 2, outputUSD: 10, sortIndex: 4),
        LLMModel(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", vendor: .anthropic, agents: [.claude, .copilot], tier: "Fast", inputUSD: 1, outputUSD: 5, sortIndex: 5),
        LLMModel(id: "claude-fable-5", name: "Claude Fable 5", vendor: .anthropic, agents: [.claude], tier: "Previous", inputUSD: 10, outputUSD: 50, sortIndex: 6),
        LLMModel(id: "claude-opus-4-8", name: "Claude Opus 4.8", vendor: .anthropic, agents: [.claude], tier: "Previous", inputUSD: 5, outputUSD: 25, sortIndex: 7),
        LLMModel(id: "claude-opus-4-7", name: "Claude Opus 4.7", vendor: .anthropic, agents: [.claude], tier: "Previous", inputUSD: 5, outputUSD: 25, sortIndex: 8),
        LLMModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", vendor: .anthropic, agents: [.claude], tier: "Previous", inputUSD: 3, outputUSD: 15, sortIndex: 9),

        // OpenAI — GPT-6 and the GPT-5.6 family still on the API.
        LLMModel(id: "gpt-6-astra", name: "GPT-6 Astra", vendor: .openai, agents: [.codex, .copilot], tier: "Frontier", inputUSD: 10, outputUSD: 50, sortIndex: 10),
        LLMModel(id: "gpt-6-sol", name: "GPT-6 Sol", vendor: .openai, agents: [.codex, .copilot], tier: "Balanced", inputUSD: 2, outputUSD: 10, sortIndex: 11),
        LLMModel(id: "gpt-6-luna", name: "GPT-6 Luna", vendor: .openai, agents: [.codex, .copilot], tier: "Fast", inputUSD: 0.10, outputUSD: 0.50, sortIndex: 12),
        LLMModel(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", vendor: .openai, agents: [.codex, .copilot], tier: "Frontier", inputUSD: 4, outputUSD: 20, sortIndex: 13),
        LLMModel(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", vendor: .openai, agents: [.codex, .copilot], tier: "Balanced", inputUSD: 2, outputUSD: 12, sortIndex: 14),
        LLMModel(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", vendor: .openai, agents: [.codex], tier: "Fast", inputUSD: 0.20, outputUSD: 1.20, sortIndex: 15),

        // Google — Gemini text models used by Gemini CLI and agents.
        LLMModel(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", vendor: .google, agents: [.gemini], tier: "Balanced", inputUSD: 0.75, outputUSD: 3.75, sortIndex: 16),
        LLMModel(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash", vendor: .google, agents: [.gemini], tier: "Previous", inputUSD: 0.75, outputUSD: 3.75, sortIndex: 17),
        LLMModel(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", vendor: .google, agents: [.gemini], tier: "Previous", inputUSD: 0.75, outputUSD: 3.75, sortIndex: 18),
        LLMModel(id: "gemini-3.5-flash", name: "Gemini 3.5 Flash", vendor: .google, agents: [.gemini], tier: "Previous", inputUSD: 1.50, outputUSD: 9, sortIndex: 19),
        LLMModel(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", vendor: .google, agents: [.gemini], tier: "Fast", inputUSD: 0.30, outputUSD: 2.50, sortIndex: 20),
        LLMModel(id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro", vendor: .google, agents: [.gemini], tier: "Frontier", inputUSD: 2, outputUSD: 12, sortIndex: 21),

        // xAI — Grok models served for coding.
        LLMModel(id: "grok-4.7", name: "Grok 4.7", vendor: .xai, agents: [.grok], tier: "Frontier", inputUSD: 2, outputUSD: 6, sortIndex: 22),
        LLMModel(id: "grok-4.6", name: "Grok 4.6", vendor: .xai, agents: [.grok], tier: "Balanced", inputUSD: 2, outputUSD: 6, sortIndex: 23),
        LLMModel(id: "grok-4.5", name: "Grok 4.5", vendor: .xai, agents: [.grok], tier: "Previous", inputUSD: 2, outputUSD: 6, sortIndex: 24),
        LLMModel(id: "grok-4.3", name: "Grok 4.3", vendor: .xai, agents: [.grok], tier: "Fast", inputUSD: 1.25, outputUSD: 2.50, sortIndex: 25),
        LLMModel(id: "grok-build-0.1", name: "Grok Build 0.1", vendor: .xai, agents: [.grok], tier: "Fast", inputUSD: 1, outputUSD: 2, sortIndex: 26),
    ]

    static let priceFootnote = "Counted from local transcripts. Cost uses list price for input and output. Cache reads are 10% of input, cache writes 125%."

    static func match(_ id: String) -> LLMModel? {
        if let exact = all.first(where: { $0.id == id }) { return exact }
        return all
            .filter { id.hasPrefix($0.id) || $0.id.hasPrefix(id) }
            .max { $0.id.count < $1.id.count }
    }

    static func vendor(for id: String) -> ModelVendor {
        if let matched = match(id) { return matched.vendor }
        let lower = id.lowercased()
        if lower.contains("claude") { return .anthropic }
        if lower.hasPrefix("gpt") || lower.contains("codex") { return .openai }
        if lower.contains("gemini") { return .google }
        if lower.contains("grok") { return .xai }
        return .other
    }
}

struct ModelUsageRow: Identifiable {
    let model: LLMModel
    let tokens: Int
    let fraction: Double
    let measuredCost: Double

    var id: String { model.id }

    var tokenLabel: String { TokenFormat.string(for: tokens) }
    var costLabel: String {
        guard measuredCost > 0 else { return "" }
        return "~\(CostEstimate.summary(measuredCost))"
    }
}

struct ModelGroup: Identifiable {
    let vendor: ModelVendor
    let rows: [ModelUsageRow]
    var id: String { vendor.rawValue }
}
