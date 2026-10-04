import Foundation
import SQLite3

struct SubscriptionStatus: Identifiable {
    let id: String
    let product: String
    let planName: String
    let detail: String
    let iconName: String
    let agent: AgentType?
    let signedIn: Bool
}

struct SubscriptionSnapshot {
    var subscriptions: [SubscriptionStatus]
    var rateLimits: [RateLimitItem]
    var limitsNote: String
    /// Model id Cursor has selected, such as `grok-4.7`.
    var cursorModelID: String?
}

/// Reads plan names from local agent configs. Tokens and secrets stay on disk.
enum SubscriptionReader {
    static func load() -> SubscriptionSnapshot {
        let claude = readClaude()
        var subscriptions = [claude.status, readCodex(), readCursor(), readGemini()]
        let missing = missingProducts()
        if !missing.isEmpty {
            subscriptions.append(
                SubscriptionStatus(
                    id: "missing",
                    product: missing.joined(separator: " · "),
                    planName: "Not signed in",
                    detail: "No local account on this Mac.",
                    iconName: "person.crop.circle.badge.questionmark",
                    agent: nil,
                    signedIn: false
                )
            )
        }
        return SubscriptionSnapshot(
            subscriptions: subscriptions,
            rateLimits: claude.limits,
            limitsNote: claude.note,
            cursorModelID: readCursorModel()?.modelID
        )
    }

    // MARK: Claude

    private static func readClaude() -> (status: SubscriptionStatus, limits: [RateLimitItem], note: String) {
        let home = homeDirectory()
        let accountURL = home.appendingPathComponent(".claude.json")
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        guard let root = jsonObject(at: accountURL),
              let account = root["oauthAccount"] as? [String: Any],
              let orgType = account["organizationType"] as? String,
              !orgType.isEmpty
        else {
            return (
                SubscriptionStatus(
                    id: "claude",
                    product: "Claude Code",
                    planName: "Not signed in",
                    detail: "No Claude account in ~/.claude.json.",
                    iconName: AgentType.claude.iconName,
                    agent: .claude,
                    signedIn: false
                ),
                [],
                ""
            )
        }

        let tier = account["organizationRateLimitTier"] as? String ?? ""
        let plan = claudePlanName(orgType: orgType, tier: tier)
        let model = (jsonObject(at: settingsURL)?["model"] as? String).map { "Model \($0)" }
        let extra = (account["hasExtraUsageEnabled"] as? Bool) == true ? "Extra usage on" : "Extra usage off"
        let detail = [model, extra].compactMap { $0 }.joined(separator: " · ")
        let usage = usageLimits(from: root, now: Date())

        return (
            SubscriptionStatus(
                id: "claude",
                product: "Claude Code",
                planName: plan,
                detail: detail,
                iconName: AgentType.claude.iconName,
                agent: .claude,
                signedIn: true
            ),
            usage.limits,
            usage.note
        )
    }

    static func claudePlanName(orgType: String, tier: String) -> String {
        let blob = (orgType + " " + tier).lowercased()
        if blob.contains("20x") { return "Claude Max 20x" }
        if blob.contains("5x") { return "Claude Max 5x" }
        if blob.contains("max") { return "Claude Max" }
        switch orgType {
        case "claude_pro": return "Claude Pro"
        case "claude_max": return "Claude Max"
        case "claude_team": return "Claude Team"
        case "claude_enterprise": return "Claude Enterprise"
        case "claude_free": return "Claude Free"
        default:
            let words = orgType.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    static func usageLimits(from root: [String: Any], now: Date) -> (limits: [RateLimitItem], note: String) {
        guard let cache = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cache["utilization"] as? [String: Any],
              let rawLimits = utilization["limits"] as? [[String: Any]]
        else {
            return ([], "")
        }

        let limits: [RateLimitItem] = rawLimits.compactMap { item in
            guard let kind = item["kind"] as? String,
                  let percent = intValue(item["percent"])
            else { return nil }
            let title: String
            switch kind {
            case "session": title = "Session"
            case "weekly_all": title = "Weekly"
            default: title = kind.replacingOccurrences(of: "_", with: " ").capitalized
            }
            let reset = (item["resets_at"] as? String).flatMap(parseISODate)
            // A saved percent only describes its window until that window resets.
            if let reset, reset <= now { return nil }
            let timer = reset.map(resetLabel) ?? "No reset time"
            return RateLimitItem(title: title, percent: percent, resetTimer: timer)
        }

        let fetched = (cache["fetchedAtMs"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        let note: String
        if let fetched {
            let stamp = shortDate.string(from: fetched)
            note = "Claude usage snapshot from \(stamp). Open Claude Code to refresh it."
        } else {
            note = "Claude usage snapshot from the local account file."
        }
        return (limits, note)
    }

    // MARK: Codex / ChatGPT

    private static func readCodex() -> SubscriptionStatus {
        let home = homeDirectory()
        let authURL = home.appendingPathComponent(".codex/auth.json")
        guard let auth = jsonObject(at: authURL) else {
            return unsigned(id: "codex", product: "Codex", icon: AgentType.codex.iconName, agent: .codex, detail: "No Codex account in ~/.codex.")
        }

        let mode = auth["auth_mode"] as? String
        let model = codexModel(in: home)
        if mode == "chatgpt",
           let tokens = auth["tokens"] as? [String: Any],
           let idToken = tokens["id_token"] as? String,
           let payload = jwtPayload(idToken),
           let claim = payload["https://api.openai.com/auth"] as? [String: Any],
           let planType = claim["chatgpt_plan_type"] as? String
        {
            let until = (claim["chatgpt_subscription_active_until"] as? String).flatMap(parseISODate)
            let renew = until.map(renewLabel)
            let detail = [model.map { "Model \($0)" }, renew].compactMap { $0 }.joined(separator: " · ")
            return SubscriptionStatus(
                id: "codex",
                product: "Codex",
                planName: chatGPTPlanName(planType),
                detail: detail.isEmpty ? "ChatGPT subscription" : detail,
                iconName: AgentType.codex.iconName,
                agent: .codex,
                signedIn: true
            )
        }

        if auth["OPENAI_API_KEY"] is String {
            return SubscriptionStatus(
                id: "codex",
                product: "Codex",
                planName: "API key",
                detail: [model.map { "Model \($0)" }, "Billed to the API key, not a ChatGPT plan"].compactMap { $0 }.joined(separator: " · "),
                iconName: AgentType.codex.iconName,
                agent: .codex,
                signedIn: true
            )
        }

        return unsigned(id: "codex", product: "Codex", icon: AgentType.codex.iconName, agent: .codex, detail: "Codex is installed, with no ChatGPT plan saved.")
    }

    private static func chatGPTPlanName(_ planType: String) -> String {
        switch planType.lowercased() {
        case "go": return "ChatGPT Go"
        case "plus": return "ChatGPT Plus"
        case "pro": return "ChatGPT Pro"
        case "team": return "ChatGPT Team"
        case "enterprise": return "ChatGPT Enterprise"
        case "free": return "ChatGPT Free"
        default: return "ChatGPT \(planType.capitalized)"
        }
    }

    private static func codexModel(in home: URL) -> String? {
        let config = home.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model ") || trimmed.hasPrefix("model=") else { continue }
            guard !trimmed.contains("reasoning") else { continue }
            let value = trimmed.split(separator: "=", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: Cursor

    private static func readCursor() -> SubscriptionStatus {
        guard let membership = cursorValue("cursorAuth/stripeMembershipType"), !membership.isEmpty else {
            return unsigned(id: "cursor", product: "Cursor", icon: "cursorarrow.rays", agent: nil, detail: "No Cursor membership in local app storage.")
        }
        let teamName = cursorTeamName()
        let using = readCursorModel().map { selection -> String in
            selection.note.isEmpty ? "Using \(selection.name)" : "Using \(selection.name) · \(selection.note)"
        }
        let combined = [teamName.map { "Team \($0)" }, using].compactMap { $0 }.joined(separator: " · ")
        let detail = combined.isEmpty ? "Signed in to Cursor" : combined
        return SubscriptionStatus(
            id: "cursor",
            product: "Cursor",
            planName: cursorPlanName(membership),
            detail: detail,
            iconName: "cursorarrow.rays",
            agent: nil,
            signedIn: true
        )
    }

    private struct CursorSelection {
        let modelID: String
        let name: String
        let note: String
    }

    /// Cursor stores the composer model in a small JSON blob, separate from the account token.
    private static func readCursorModel() -> CursorSelection? {
        guard let raw = cursorValue("cursor/applicationOpenModelAppliedConfig"),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["selectedModels"] as? [[String: Any]],
              let first = models.first,
              let modelID = first["modelId"] as? String,
              !modelID.isEmpty,
              modelID != "default"
        else { return nil }

        let name = LLMCatalog.all.first { $0.id == modelID }?.name ?? modelID
        var notes: [String] = []
        if let parameters = first["parameters"] as? [[String: Any]] {
            for parameter in parameters {
                guard let id = parameter["id"] as? String, let value = parameter["value"] as? String else { continue }
                switch id {
                case "reasoning_effort" where value != "none" && value != "false":
                    notes.append(value)
                case "context":
                    notes.append(value)
                case "fast" where value == "true":
                    notes.append("fast")
                default:
                    break
                }
            }
        }
        return CursorSelection(modelID: modelID, name: name, note: notes.joined(separator: " · "))
    }

    private static func cursorPlanName(_ membership: String) -> String {
        switch membership.lowercased() {
        case "pro": return "Cursor Pro"
        case "pro_plus", "proplus": return "Cursor Pro+"
        case "ultra": return "Cursor Ultra"
        case "business": return "Cursor Business"
        case "enterprise": return "Cursor Enterprise"
        case "free", "hobby": return "Cursor Free"
        default: return "Cursor \(membership.capitalized)"
        }
    }

    private static func cursorTeamName() -> String? {
        guard let raw = cursorValue("cursorAuth/cachedTeam"),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.isEmpty
        else { return nil }
        return name
    }

    private static func cursorValue(_ key: String) -> String? {
        let path = homeDirectory()
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    // MARK: Gemini and the rest

    private static func readGemini() -> SubscriptionStatus {
        let token = homeDirectory().appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        let exists = FileManager.default.fileExists(atPath: token.path)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: token.path)[.size]) as? NSNumber
        if exists && (bytes?.intValue ?? 0) > 0 {
            return SubscriptionStatus(
                id: "gemini",
                product: "Gemini CLI",
                planName: "Google account",
                detail: "Signed in. The Gemini plan name is not stored locally.",
                iconName: AgentType.gemini.iconName,
                agent: .gemini,
                signedIn: true
            )
        }
        return unsigned(id: "gemini", product: "Gemini CLI", icon: AgentType.gemini.iconName, agent: .gemini, detail: "No Gemini session on this Mac.")
    }

    private static func missingProducts() -> [String] {
        var names: [String] = []
        if !FileManager.default.fileExists(atPath: homeDirectory().appendingPathComponent(".grok").path)
            && !FileManager.default.fileExists(atPath: homeDirectory().appendingPathComponent(".xai").path) {
            names.append("Grok")
        }
        let copilot = homeDirectory().appendingPathComponent(".copilot/config.json")
        let copilotText = (try? String(contentsOf: copilot, encoding: .utf8)) ?? ""
        if copilotText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names.append("Copilot")
        }
        return names
    }

    private static func unsigned(id: String, product: String, icon: String, agent: AgentType?, detail: String) -> SubscriptionStatus {
        SubscriptionStatus(id: id, product: product, planName: "Not signed in", detail: detail, iconName: icon, agent: agent, signedIn: false)
    }

    // MARK: Parsing

    private static func homeDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Decodes a JWT payload in memory. The token itself is never stored.
    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private static func resetLabel(_ date: Date) -> String {
        let days = dayDistance(to: date)
        if days > 1 { return "Resets in \(days)d" }
        if days == 1 { return "Resets tomorrow" }
        if days == 0 { return "Resets today" }
        return "Reset \(abs(days))d ago"
    }

    private static func renewLabel(_ date: Date) -> String {
        let days = dayDistance(to: date)
        if days > 1 { return "Renews in \(days) days" }
        if days == 1 { return "Renews tomorrow" }
        if days == 0 { return "Renews today" }
        return "Ended \(abs(days))d ago"
    }

    private static func dayDistance(to date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
