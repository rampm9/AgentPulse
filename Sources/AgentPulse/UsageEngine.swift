import Foundation
import Darwin

/// Local transcript totals and live allowance checks.
/// Counting rules follow AgentBar's collectors (MIT), which port Omarchy's usage scripts.
enum UsageEngine {
    struct ModelTokens: Sendable {
        var id: String
        var agent: AgentType
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int

        var total: Int { input + output + cacheRead + cacheWrite }

        static func + (lhs: ModelTokens, rhs: ModelTokens) -> ModelTokens {
            ModelTokens(
                id: lhs.id,
                agent: lhs.agent,
                input: lhs.input + rhs.input,
                output: lhs.output + rhs.output,
                cacheRead: lhs.cacheRead + rhs.cacheRead,
                cacheWrite: lhs.cacheWrite + rhs.cacheWrite
            )
        }
    }

    struct Scan: Sendable {
        var days: [Int]
        var models: [ModelTokens]
    }

    struct Snapshot: Sendable {
        var weekDates: [Date]
        var claude: Scan
        var codex: Scan
        var claudeLimits: [RateLimitItem]
        var codexLimits: [RateLimitItem]
        var claudeNote: String
        var codexNote: String
        var claudeSignInExpired: Bool

        static let empty = Snapshot(
            weekDates: datesForWeek(around: Date()),
            claude: Scan(days: Array(repeating: 0, count: 7), models: []),
            codex: Scan(days: Array(repeating: 0, count: 7), models: []),
            claudeLimits: [],
            codexLimits: [],
            claudeNote: "",
            codexNote: "",
            claudeSignInExpired: false
        )
    }

    static func load() async -> Snapshot {
        let now = Date()
        async let claude = Task.detached(priority: .utility) { scanClaude(now: now) }.value
        async let codex = Task.detached(priority: .utility) { scanCodex(now: now) }.value
        async let claudeLimits = claudeLimitProbe()
        async let codexLimits = codexLimitProbe()
        let (claudeScan, codexScan, claudeProbe, codexProbe) = await (claude, codex, claudeLimits, codexLimits)
        return Snapshot(
            weekDates: datesForWeek(around: now),
            claude: claudeScan,
            codex: codexScan,
            claudeLimits: claudeProbe.limits,
            codexLimits: codexProbe.limits,
            claudeNote: claudeProbe.note,
            codexNote: codexProbe.note,
            claudeSignInExpired: claudeProbe.signInExpired
        )
    }

    // MARK: - Claude transcripts

    private static func scanClaude(now: Date) -> Scan {
        let root = home.appendingPathComponent(".claude/projects")
        let calendar = Calendar.current
        let dates = datesForWeek(around: now)
        let keys = dates.map { dayKey($0, calendar: calendar) }
        var days = Array(repeating: 0, count: 7)
        var buckets: [String: ModelTokens] = [:]
        var seen: Set<String> = []
        var sequence = 0
        forEachJSONL(under: root, modifiedAfter: nil) { file, object in
            sequence += 1
            let lineKey = "\(file.path):\(sequence)"
            guard let message = object["message"] as? [String: Any] else { return }
            let isAssistant = object["type"] as? String == "assistant" || message["role"] as? String == "assistant"
            guard isAssistant, let usage = message["usage"] as? [String: Any], !usage.isEmpty else { return }
            let messageID = text(message["id"]) ?? text(object["messageId"]) ?? lineKey
            guard seen.insert(messageID).inserted else { return }
            let input = rounded(usage["input_tokens"])
            let output = rounded(usage["output_tokens"])
            let cacheRead = rounded(usage["cache_read_input_tokens"])
            let cacheWrite = rounded(usage["cache_creation_input_tokens"])
            let total = input + output + cacheRead + cacheWrite
            guard total > 0 else { return }
            let model = text(message["model"]) ?? text(object["model"]) ?? "claude"
            add(model: model, agent: .claude, input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, into: &buckets)
            let day = dayKey(from: object["timestamp"] ?? message["timestamp"], now: now, calendar: calendar)
            if let index = keys.firstIndex(of: day) { days[index] += total }
        }
        return Scan(days: days, models: Array(buckets.values))
    }

    // MARK: - Codex sessions

    private static func scanCodex(now: Date) -> Scan {
        let calendar = Calendar.current
        let dates = datesForWeek(around: now)
        let keys = dates.map { dayKey($0, calendar: calendar) }
        var days = Array(repeating: 0, count: 7)
        var buckets: [String: ModelTokens] = [:]
        let cutoff = now.addingTimeInterval(-30 * 24 * 3600)
        let roots = ["sessions", "archived_sessions"].map { home.appendingPathComponent(".codex/\($0)") }
        for root in roots {
            scanCodexFiles(under: root, cutoff: cutoff, now: now, calendar: calendar, keys: keys, days: &days, buckets: &buckets)
        }
        return Scan(days: days, models: Array(buckets.values))
    }

    private static func scanCodexFiles(
        under root: URL,
        cutoff: Date,
        now: Date,
        calendar: Calendar,
        keys: [String],
        days: inout [Int],
        buckets: inout [String: ModelTokens]
    ) {
        let files = jsonlFiles(under: root, modifiedAfter: cutoff)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            var model = "codex"
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("token_count") || line.contains("turn_context") else { continue }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if object["type"] as? String == "turn_context" {
                    let payload = object["payload"] as? [String: Any] ?? [:]
                    model = text(payload["model"]) ?? text(payload["model_slug"]) ?? model
                    continue
                }
                var payload = object["payload"] as? [String: Any] ?? object
                if object["type"] as? String == "response_item", let inner = payload["payload"] as? [String: Any] {
                    payload = inner
                }
                guard payload["type"] as? String == "token_count" else { continue }
                let info = payload["info"] as? [String: Any] ?? [:]
                let usage = info["last_token_usage"] as? [String: Any] ?? [:]
                let cacheRead = truncated(usage["cached_input_tokens"])
                let cacheWrite = truncated(usage["cache_write_input_tokens"])
                let input = max(0, truncated(usage["input_tokens"]) - cacheRead - cacheWrite)
                let output = truncated(usage["output_tokens"])
                guard input + output + cacheRead + cacheWrite > 0 else { continue }
                add(model: model, agent: .codex, input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, into: &buckets)
                let stamp = object["timestamp"] ?? payload["timestamp"] ?? modified.timeIntervalSince1970
                let day = dayKey(from: stamp, now: now, calendar: calendar)
                if let index = keys.firstIndex(of: day) { days[index] += input + output + cacheRead + cacheWrite }
            }
        }
    }

    // MARK: - Claude limits

    private struct Probe {
        var limits: [RateLimitItem]
        var note: String
        var signInExpired = false
    }

    private static func claudeLimitProbe() async -> Probe {
        let probe = await claudeLimitProbeLive()
        guard probe.limits.isEmpty, let desktop = desktopLimits() else { return probe }
        var filled = probe
        filled.limits = desktop.limits
        filled.note = [probe.note, desktop.note].filter { !$0.isEmpty }.joined(separator: " ")
        return filled
    }

    /// The Claude desktop app writes the latest five-hour (`fh`) and seven-day (`sd`) percents here.
    private static func desktopLimits() -> (limits: [RateLimitItem], note: String)? {
        let url = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let root = jsonObject(at: url) else { return nil }
        return limits(fromDesktopHistory: root)
    }

    static func limits(fromDesktopHistory root: [String: Any]) -> (limits: [RateLimitItem], note: String)? {
        guard let samples = root["samples"] as? [[String: Any]],
              let last = samples.last,
              let usage = last["u"] as? [String: Any]
        else { return nil }
        var limits: [RateLimitItem] = []
        if usage["fh"] != nil {
            limits.append(RateLimitItem(title: "Session", percent: min(100, max(0, rounded(usage["fh"]))), resetTimer: "5-hour"))
        }
        if usage["sd"] != nil {
            limits.append(RateLimitItem(title: "Weekly", percent: min(100, max(0, rounded(usage["sd"]))), resetTimer: "7-day"))
        }
        guard !limits.isEmpty else { return nil }
        let when = (last["t"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        let stamp = when.map { formatter.string(from: $0) } ?? "the Claude app"
        return (limits, "These percents are the Claude app's reading from \(stamp).")
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func claudeLimitProbeLive() async -> Probe {
        let keychain = await readClaudeKeychain()
        switch keychain {
        case .denied:
            return Probe(limits: [], note: "Keychain access was denied. The bars below are the last limits Claude Code saved.")
        case .notFound:
            return Probe(limits: [], note: "No Claude Code sign-in in Keychain. The bars below are the last limits saved on this Mac.")
        case .failed:
            return Probe(limits: [], note: "Couldn't read the Claude Code sign-in. The bars below are the last limits saved on this Mac.")
        case .found(let data):
            guard let login = parseClaudeLogin(data), !login.token.isEmpty else {
                return Probe(limits: [], note: "Claude Code's saved sign-in could not be read. The bars below are the last limits saved on this Mac.")
            }
            if login.expiresAtMs > 0, Double(login.expiresAtMs) <= Date().timeIntervalSince1970 * 1000 {
                let expired = Date(timeIntervalSince1970: Double(login.expiresAtMs) / 1000)
                let formatter = DateFormatter()
                formatter.dateFormat = "d MMM yyyy"
                return Probe(
                    limits: [],
                    note: "Claude Code's sign-in expired \(formatter.string(from: expired)). Open Claude Code and sign in again so a plan change, including Max, is saved on this Mac.",
                    signInExpired: true
                )
            }
            return await fetchClaudeLimits(token: login.token)
        }
    }

    private static func fetchClaudeLimits(token: String) async -> Probe {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return Probe(limits: [], note: "Anthropic didn't return limits. The bars below are the last limits Claude Code saved.")
            }
            let limits = parseClaudeLimits(data)
            guard !limits.isEmpty else {
                return Probe(limits: [], note: "Anthropic returned no limits. The bars below are the last limits Claude Code saved.")
            }
            return Probe(limits: limits, note: "Claude limits just fetched from Anthropic.")
        } catch {
            return Probe(limits: [], note: "Couldn't reach Anthropic. The bars below are the last limits Claude Code saved.")
        }
    }

    private static func parseClaudeLimits(_ data: Data) -> [RateLimitItem] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let weekly = (payload["seven_day_oauth_apps"] as? [String: Any]).flatMap { $0.isEmpty ? nil : $0 } ?? payload["seven_day"] as? [String: Any]
        let session = payload["five_hour"] as? [String: Any]
        var items: [RateLimitItem] = []
        if let session, let item = limitItem(title: "Session", utilization: session["utilization"], resets: session["resets_at"]) {
            items.append(item)
        }
        if let weekly, let item = limitItem(title: "Weekly", utilization: weekly["utilization"], resets: weekly["resets_at"]) {
            items.append(item)
        }
        return items
    }

    private static func limitItem(title: String, utilization: Any?, resets: Any?) -> RateLimitItem? {
        guard let raw = doubleValue(utilization), raw >= 0 else { return nil }
        let fraction = raw > 1 ? min(1, raw / 100) : min(1, raw)
        let percent = Int((fraction * 100).rounded())
        let reset = parseReset(resets).map(resetLabel) ?? "No reset time"
        return RateLimitItem(title: title, percent: percent, resetTimer: reset)
    }

    // MARK: - Codex limits

    private static func codexLimitProbe() async -> Probe {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: codexLimitProbeBlocking())
            }
        }
    }

    private static func codexLimitProbeBlocking() -> Probe {
        guard let codex = locateCodex() else {
            return Probe(limits: [], note: "Codex token counts are from local sessions. The codex command was not found, so live limits are unavailable.")
        }
        let process = Process()
        process.executableURL = codex
        process.arguments = ["-s", "read-only", "-a", "on-request", "app-server"]
        process.environment = codexEnvironment()
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        signal(SIGPIPE, SIG_IGN)
        do {
            try process.run()
        } catch {
            return Probe(limits: [], note: "Codex token counts are from local sessions. Live limits could not be started.")
        }
        defer { stop(process, input: input, output: output) }
        let session = RPCSession(input: input.fileHandleForWriting, output: output.fileHandleForReading)
        do {
            _ = try session.request(id: 1, method: "initialize", params: ["clientInfo": ["name": "agentpulse", "version": "0.1"]], timeout: 8)
            try session.send(["method": "initialized", "params": [String: Any]()])
            let account = try session.request(id: 2, method: "account/read", timeout: 4)
            let limits = try session.request(id: 3, method: "account/rateLimits/read", timeout: 4)
            let rateLimits = (limits["result"] as? [String: Any])?["rateLimits"] as? [String: Any] ?? [:]
            let accountInfo = (account["result"] as? [String: Any])?["account"] as? [String: Any] ?? [:]
            let plan = text(rateLimits["planType"]) ?? text(accountInfo["planType"]) ?? ""
            let items = [rateLimits["primary"], rateLimits["secondary"]].compactMap(codexWindow)
            let note = plan.isEmpty ? "Codex limits from the local codex command." : "Codex \(plan) limits from the local codex command."
            return Probe(limits: items, note: items.isEmpty ? "Codex token counts are from local sessions. The codex command returned no limits." : note)
        } catch {
            return Probe(limits: [], note: "Codex token counts are from local sessions. Live limits were unavailable.")
        }
    }

    private static func codexWindow(_ value: Any?) -> RateLimitItem? {
        guard let window = value as? [String: Any] else { return nil }
        guard let used = doubleValue(window["usedPercent"]), used >= 0 else { return nil }
        let minutes = truncated(window["windowDurationMins"])
        let title: String
        switch minutes {
        case 10080: title = "Weekly"
        case let value where value != 0 && value % 60 == 0: title = "\(value / 60)h"
        case let value where value != 0: title = "\(value)m"
        default: title = "Limit"
        }
        let reset = parseReset(window["resetsAt"]).map(resetLabel) ?? "No reset time"
        return RateLimitItem(title: title, percent: Int(used.rounded()), resetTimer: reset)
    }

    // MARK: - Files

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func forEachJSONL(under root: URL, modifiedAfter cutoff: Date?, _ body: (URL, [String: Any]) -> Void) {
        for file in jsonlFiles(under: root, modifiedAfter: cutoff) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"usage\"") else { continue }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                body(file, object)
            }
        }
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date?) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            if let cutoff {
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let modified, modified < cutoff { continue }
            }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func add(model: String, agent: AgentType, input: Int, output: Int, cacheRead: Int, cacheWrite: Int, into buckets: inout [String: ModelTokens]) {
        var current = buckets[model] ?? ModelTokens(id: model, agent: agent, input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
        current.input += input
        current.output += output
        current.cacheRead += cacheRead
        current.cacheWrite += cacheWrite
        buckets[model] = current
    }

    // MARK: - Dates

    static func datesForWeek(around now: Date) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func dayKey(from value: Any?, now: Date, calendar: Calendar) -> String {
        switch value {
        case let number as NSNumber:
            var seconds = number.doubleValue
            if seconds > 10_000_000_000 { seconds /= 1000 }
            guard seconds.isFinite else { break }
            return dayKey(Date(timeIntervalSince1970: seconds), calendar: calendar)
        case let string as String:
            let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = parseISO(raw) { return dayKey(date, calendar: calendar) }
            if raw.count >= 10, raw.prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }) { return String(raw.prefix(10)) }
        default:
            break
        }
        return dayKey(now, calendar: calendar)
    }

    private static func parseISO(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func parseReset(_ value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            var seconds = number.doubleValue
            if seconds > 10_000_000_000 { seconds /= 1000 }
            guard seconds > 1_000_000_000 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        case let string as String:
            return parseISO(string.replacingOccurrences(of: "Z", with: "+00:00")) ?? parseISO(string)
        default:
            return nil
        }
    }

    private static func resetLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 1 { return "Resets in \(days)d" }
        if days == 1 { return "Resets tomorrow" }
        if days == 0 { return "Resets today" }
        return "Reset \(abs(days))d ago"
    }

    // MARK: - Numbers

    private static func rounded(_ value: Any?) -> Int {
        guard let number = doubleValue(value), number.isFinite else { return 0 }
        return Int(number.rounded())
    }

    private static func truncated(_ value: Any?) -> Int {
        guard let number = doubleValue(value), number.isFinite else { return 0 }
        return Int(number.rounded(.towardZero))
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Claude Keychain

    private struct ClaudeLogin {
        var token: String
        var expiresAtMs: Int
    }

    private enum KeychainRead {
        case found(Data)
        case notFound
        case denied
        case failed
    }

    private static func readClaudeKeychain() async -> KeychainRead {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readClaudeKeychainBlocking())
            }
        }
    }

    private static func readClaudeKeychainBlocking() -> KeychainRead {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failed }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0:
            var data = output
            while let last = data.last, last == 0x0A || last == 0x0D { data.removeLast() }
            return .found(data)
        case 44:
            return .notFound
        case 36, 51, 128:
            return .denied
        default:
            return .failed
        }
    }

    private static func parseClaudeLogin(_ data: Data) -> ClaudeLogin? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = root["claudeAiOauth"] as? [String: Any],
              let token = login["accessToken"] as? String else { return nil }
        return ClaudeLogin(token: token, expiresAtMs: truncated(login["expiresAt"]))
    }

    // MARK: - Codex process

    private static func locateCodex() -> URL? {
        for directory in codexSearchPath() {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func codexSearchPath() -> [String] {
        let homePath = home.path
        let current = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return current + [
            "\(homePath)/.local/bin",
            "\(homePath)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
    }

    private static func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = codexSearchPath().filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }

    private static func stop(_ process: Process, input: Pipe, output: Pipe) {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
}

private final class RPCSession {
    private let input: FileHandle
    private let descriptor: Int32
    private var buffer = Data()

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        descriptor = output.fileDescriptor
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    func request(id: Int, method: String, params: [String: Any] = [:], timeout: TimeInterval) throws -> [String: Any] {
        do {
            try send(["id": id, "method": method, "params": params])
        } catch {
            throw CocoaError(.fileWriteUnknown)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while let line = readLine(until: deadline) {
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let messageID = message["id"] as? NSNumber,
                  messageID.doubleValue == Double(id) else { continue }
            return message
        }
        throw CocoaError(.fileReadUnknown)
    }

    private func readLine(until deadline: Date) -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var descriptorPoll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptorPoll, 1, Int32(min(remaining * 1000, Double(Int32.max)).rounded(.up)))
            if ready == 0 { return nil }
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
