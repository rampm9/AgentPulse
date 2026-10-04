import Foundation

/// Checks the plan label and limit rules, then reads this Mac once.
@main
struct ServiceChecks {
    static func main() async {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("ok  \(name)")
            } else {
                print("FAIL \(name)")
                failures.append(name)
            }
        }

        check("pro stays Pro", SubscriptionReader.claudePlanName(orgType: "claude_pro", tier: "default_claude_ai") == "Claude Pro")
        check("max org", SubscriptionReader.claudePlanName(orgType: "claude_max", tier: "") == "Claude Max")
        check("max 20x", SubscriptionReader.claudePlanName(orgType: "claude_pro", tier: "default_claude_max_20x") == "Claude Max 20x")
        check("max 5x", SubscriptionReader.claudePlanName(orgType: "claude_max", tier: "max_5x") == "Claude Max 5x")

        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let expired = ISO8601DateFormatter().string(from: now.addingTimeInterval(-86_400))
        let open = ISO8601DateFormatter().string(from: now.addingTimeInterval(86_400))
        let snapshot: [String: Any] = [
            "cachedUsageUtilization": [
                "fetchedAtMs": 1_000,
                "utilization": [
                    "limits": [
                        ["kind": "session", "percent": 2, "resets_at": expired],
                        ["kind": "weekly_all", "percent": 3, "resets_at": open],
                    ],
                ],
            ],
        ]
        let kept = SubscriptionReader.usageLimits(from: snapshot, now: now).limits
        check("closed window is dropped", kept.map(\.title) == ["Weekly"] && kept.map(\.percent) == [3])

        let desktop = UsageEngine.limits(fromDesktopHistory: [
            "samples": [
                ["t": 1_790_885_000_000, "u": ["fh": 10, "sd": 3]],
            ],
        ])
        check("desktop session and weekly", desktop?.limits.map(\.title) == ["Session", "Weekly"] && desktop?.limits.map(\.percent) == [10, 3])

        let sonnet = LLMCatalog.match("claude-sonnet-5")
        let cost = sonnet.map { CostEstimate.dollars(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0, model: $0) } ?? -1
        check("one million input tokens at list price", abs(cost - 2) < 0.001)

        let account = SubscriptionReader.load()
        let claude = account.subscriptions.first { $0.id == "claude" }
        print("plan \(claude?.planName ?? "missing") signedIn \(claude?.signedIn ?? false)")
        print("open cached limits \(account.rateLimits.map { "\($0.title) \($0.percent)%" }.joined(separator: ", "))")

        let usage = await UsageEngine.load()
        print("live or desktop limits \(usage.claudeLimits.map { "\($0.title) \($0.percent)%" }.joined(separator: ", "))")
        print("sign-in expired \(usage.claudeSignInExpired)")
        let claudeTokens = usage.claude.models.reduce(0) { $0 + $1.total }
        let codexTokens = usage.codex.models.reduce(0) { $0 + $1.total }
        print("claude transcript tokens \(claudeTokens)")
        print("codex transcript tokens \(codexTokens)")
        check("claude transcripts were read", claudeTokens > 0)
        check("a limit percent is on screen", !usage.claudeLimits.isEmpty || !account.rateLimits.isEmpty)

        if failures.isEmpty {
            print("all checks passed")
        } else {
            fputs("failed: \(failures.joined(separator: ", "))\n", stderr)
            exit(1)
        }
    }
}
