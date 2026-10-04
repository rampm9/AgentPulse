import SwiftUI
import AppKit

enum ActiveViewMode {
    case dashboard
    case settings
}

@MainActor
class StateStore: ObservableObject {
    static let shared = StateStore()

    @Published var activeViewMode: ActiveViewMode = .dashboard
    /// `nil` shows every vendor. A value filters the catalog to that agent.
    @Published var agentFilter: AgentType? = nil
    @Published var selectedAgent: AgentType = .claude
    @Published var currentTheme: ThemePreset = .everforest
    
    // Agent Toggles (Settings)
    @Published var claudeEnabled: Bool = true
    @Published var codexEnabled: Bool = true
    @Published var grokEnabled: Bool = true
    
    // General Settings
    @Published var refreshIntervalSeconds: Int = 900
    @Published var showPercentageInBar: Bool = true
    @Published var agentCommand: String = "claude"
    @Published var recordsFolder: String = "~/Library/Application Support/AgentBar/records"
    @Published var launchAtLogin: Bool = true
    
    // Sync Settings
    @Published var syncSettings: SyncSettings = SyncSettings()
    
    @Published var subscriptions: [SubscriptionStatus] = []
    @Published var limitsNote: String = ""
    @Published var cursorModelID: String? = nil

    // Fallback Claude limits from ~/.claude.json, used until a live reading arrives.
    @Published var rateLimits: [RateLimitItem] = []
    @Published var usage: UsageEngine.Snapshot = .empty
    private var usageInFlight = false

    var theme: ThemeColors {
        currentTheme.themeColors
    }

    init() {
        refreshSubscriptions()
    }

    var statusSymbolName: String {
        agentFilter?.iconName ?? "sparkles"
    }

    /// Plans for the chip on screen. Claude stays Claude even when Cursor is using a Claude model.
    var plansOnScreen: [SubscriptionStatus] {
        if let agentFilter {
            return subscriptions.filter { $0.agent == agentFilter }
        }
        return subscriptions.filter { $0.signedIn && $0.id != "missing" }
    }

    var subscriptionHeadline: String {
        let plan = plansOnScreen.first { $0.id == "claude" } ?? plansOnScreen.first
        guard let plan else { return "No subscription found" }
        return headline(for: plan)
    }

    func headline(for plan: SubscriptionStatus) -> String {
        if plan.id == "cursor", let name = activeCursorModel?.name {
            return "\(plan.planName) · \(name)"
        }
        var name = plan.signedIn ? plan.planName : "\(plan.product) not signed in"
        if plan.id == "claude", usage.claudeSignInExpired {
            name += " · sign-in expired"
        }
        return name
    }

    func detail(for plan: SubscriptionStatus) -> String {
        if plan.id == "claude", usage.claudeSignInExpired, !usage.claudeNote.isEmpty {
            return usage.claudeNote
        }
        return plan.detail
    }

    private var activeCursorModel: LLMModel? {
        guard let cursorModelID else { return nil }
        return LLMCatalog.all.first { $0.id == cursorModelID }
    }

    func refreshSubscriptions() {
        let snapshot = SubscriptionReader.load()
        subscriptions = snapshot.subscriptions
        rateLimits = snapshot.rateLimits
        limitsNote = snapshot.limitsNote
        cursorModelID = snapshot.cursorModelID
    }

    func refreshUsage() {
        guard !usageInFlight else { return }
        usageInFlight = true
        Task { @MainActor in
            let loaded = await UsageEngine.load()
            self.usage = loaded
            usageInFlight = false
        }
    }

    var fullestLimitPercent: Int {
        displayedLimits.map(\.percent).max() ?? 0
    }

    var displayedLimits: [RateLimitItem] {
        switch agentFilter {
        case .codex:
            return usage.codexLimits
        case .claude:
            return usage.claudeLimits.isEmpty ? rateLimits : usage.claudeLimits
        case nil:
            let claude = usage.claudeLimits.isEmpty ? rateLimits : usage.claudeLimits
            return tagged(claude, "Claude") + tagged(usage.codexLimits, "Codex")
        default:
            return []
        }
    }

    var displayedLimitsNote: String {
        switch agentFilter {
        case .codex:
            return usage.codexNote
        case .claude:
            return usage.claudeNote.isEmpty ? limitsNote : usage.claudeNote
        case nil:
            let notes = [usage.claudeNote.isEmpty ? limitsNote : usage.claudeNote, usage.codexNote]
            return notes.filter { !$0.isEmpty }.joined(separator: " ")
        default:
            return ""
        }
    }

    var tokensByDay: [DayUsageItem] {
        let counts = dayCounts
        let peak = counts.max() ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return zip(usage.weekDates, counts).map { date, tokens in
            let isToday = Calendar.current.isDateInToday(date)
            let label = isToday ? "Today" : formatter.string(from: date)
            let fraction = peak > 0 ? Double(tokens) / Double(peak) : 0
            return DayUsageItem(dayLabel: label, tokenString: tokens == 0 ? "0" : TokenFormat.string(for: tokens), fraction: fraction)
        }
    }

    private var dayCounts: [Int] {
        switch agentFilter {
        case .claude: return padded(usage.claude.days)
        case .codex: return padded(usage.codex.days)
        case nil: return zip(padded(usage.claude.days), padded(usage.codex.days)).map(+)
        default: return Array(repeating: 0, count: 7)
        }
    }

    private func padded(_ days: [Int]) -> [Int] {
        if days.count == 7 { return days }
        return Array(repeating: 0, count: 7)
    }

    private func tagged(_ items: [RateLimitItem], _ name: String) -> [RateLimitItem] {
        items.map { RateLimitItem(title: "\(name) \($0.title)", percent: $0.percent, resetTimer: $0.resetTimer) }
    }

    func select(agent: AgentType?) {
        agentFilter = agent
        if let agent {
            selectedAgent = agent
        }
    }

    func modelGroups() -> [ModelGroup] {
        let recorded = visibleModels()
        let peak = recorded.map(\.total).max() ?? 0
        let rows = recorded.map { tokens -> (vendor: ModelVendor, row: ModelUsageRow) in
            let known = LLMCatalog.match(tokens.id)
            let model = known ?? LLMModel(
                id: tokens.id,
                name: tokens.id,
                vendor: LLMCatalog.vendor(for: tokens.id),
                agents: [tokens.agent],
                tier: "Recorded",
                inputUSD: 0,
                outputUSD: 0,
                sortIndex: 1_000
            )
            let cost = CostEstimate.dollars(
                input: tokens.input,
                output: tokens.output,
                cacheRead: tokens.cacheRead,
                cacheWrite: tokens.cacheWrite,
                model: model
            )
            let fraction = peak > 0 ? Double(tokens.total) / Double(peak) : 0
            return (model.vendor, ModelUsageRow(model: model, tokens: tokens.total, fraction: fraction, measuredCost: cost))
        }
        return ModelVendor.allCases.compactMap { vendor in
            let group = rows
                .filter { $0.vendor == vendor }
                .map(\.row)
                .sorted { lhs, rhs in
                    if lhs.model.id == cursorModelID { return true }
                    if rhs.model.id == cursorModelID { return false }
                    return lhs.tokens > rhs.tokens
                }
            guard !group.isEmpty else { return nil }
            return ModelGroup(vendor: vendor, rows: group)
        }
    }

    private func visibleModels() -> [UsageEngine.ModelTokens] {
        let source: [UsageEngine.ModelTokens]
        switch agentFilter {
        case .claude: source = usage.claude.models
        case .codex: source = usage.codex.models
        case nil: source = usage.claude.models + usage.codex.models
        default: source = []
        }
        var merged: [String: UsageEngine.ModelTokens] = [:]
        for item in source where item.total > 0 {
            if let existing = merged[item.id] {
                merged[item.id] = existing + item
            } else {
                merged[item.id] = item
            }
        }
        return Array(merged.values)
    }

    func summary(for groups: [ModelGroup]) -> (tokens: Int, cost: Double, active: Int, listed: Int) {
        let rows = groups.flatMap(\.rows)
        let tokens = rows.reduce(0) { $0 + $1.tokens }
        let cost = rows.reduce(0.0) { $0 + $1.measuredCost }
        let active = rows.filter { $0.tokens > 0 }.count
        return (tokens, cost, active, rows.count)
    }
}
