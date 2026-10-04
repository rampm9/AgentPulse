# AgentPulse

AgentPulse is a macOS menu-bar app for one person who uses more than one AI coding tool and wants to see, without opening each product, which plan is signed in on this Mac and how much of that plan’s allowance is already used.

This document is the product definition for the version in this folder. It describes what the app does now, how to tell that it is working, and what is intentionally out of scope.

## Problem

Claude Code, Codex, and Cursor each keep their own plan and usage. The numbers that matter, the allowance percent and the tokens already spent, are buried in account files, a desktop app, or a vendor page. A stale percent is worse than no percent, because it looks current.

## User

A developer on macOS 14 or later who runs at least one of Claude Code, the Claude desktop app, Codex, or Cursor on this Mac. The app is for that one machine. It is not a team dashboard and it does not bill anyone.

## What this version shows

Click the menu-bar icon.

- **Plan.** The subscription saved for the agent you select. Claude’s name comes from the account file Claude Code writes (`organizationType` and the rate-limit tier). `max`, `max_5x`, and `max_20x` display as Claude Max, Claude Max 5x, and Claude Max 20x. If Claude Code’s sign-in has expired, the label says so. The plan does not change because the Claude desktop app was opened.
- **Limits.** Session and weekly percents. A saved percent is shown only while its reset time is still in the future. When Claude Code cannot ask Anthropic, because the sign-in is expired or missing, the panel uses the newest reading the Claude desktop app saved in `plan-usage-history.json` (`fh` is the 5-hour session, `sd` is the 7-day week) and prints the time of that reading.
- **This week and Models.** Token totals counted on this Mac. Claude Code counts each assistant response in `~/.claude/projects` once. Codex counts each turn’s `last_token_usage` in `~/.codex` sessions from the last 30 days. Cost is an estimate from list price: input, output, cache read at 10% of input, and cache write at 125% of input.
- **Menu bar.** The fullest limit percent currently in the panel.

The panel also lists whether Codex, Cursor, Gemini CLI, and Copilot have a local sign-in. Cursor’s token totals are not in a file this app can sum.

## What this version does not do

- It does not upgrade a plan. Logging in again does not turn Pro into Max. Max appears only after Claude Code’s own account status says Max.
- It does not read Grok. There is no Grok log on a machine that has not used it.
- It does not sync several computers, export CSV, send budget notifications, or launch at login. Those controls in Settings are not wired up.
- It is not notarized and it is not in the App Store.

## How a number is allowed on screen

| Reading | Source | Drop it when |
| :--- | :--- | :--- |
| Claude plan name | `~/.claude.json` account block | The file has no organization type |
| Claude live limits | Anthropic’s OAuth usage endpoint, using the Claude Code Keychain item | The sign-in is expired, refused, or the call fails |
| Claude fallback limits | Claude desktop `plan-usage-history.json`, newest sample | The file has no `fh` or `sd` |
| Older Claude snapshot | `cachedUsageUtilization` in `~/.claude.json` | The window’s `resets_at` is already past |
| Codex tokens | `~/.codex/sessions` and `archived_sessions` | The session file is older than 30 days |
| Codex limits | Local `codex app-server`, if the `codex` command exists | The command is missing or returns no window |

This is the same rule AgentBar uses for a closed window: a percent describes that window only until it resets. AgentBar then depends on a successful call to Anthropic. AgentPulse does that call when the Claude Code sign-in is still valid. When it is not, AgentPulse shows the Claude app’s newer local reading instead of a closed window from an old snapshot.

## Acceptance checks

From the repo root:

```sh
./Scripts/test.sh
```

That check must pass before a GitHub push. It asserts:

- Pro, Max, Max 5x, and Max 20x labels
- A limit whose reset time has passed is not shown
- A desktop history sample of session 10 and weekly 3 is read as those two bars
- List-price math for one million input tokens
- This Mac’s Claude transcripts can be counted, and some limit percent is available to draw

`./Scripts/test.sh` also prints the plan name and the percents it would show. It does not print tokens, email addresses, or sign-in secrets.

Build the app with `./Scripts/bundle.sh`, then open `AgentPulse.app`. Quit from the **Quit** button in the panel, or by right-clicking the menu-bar icon.

## Privacy

The app reads local account and transcript files. The only network call it makes itself is the Claude usage request, and only when the Claude Code access token is still valid. That token is not written to disk and is not printed. Codex limits are asked of the local `codex` command, not of a server the app contacts directly.

## Known state on a machine whose Claude sign-in has expired

The plan line stays on the last plan Claude Code saved, including **Pro**, and adds **sign-in expired**. The allowance bars switch to the Claude desktop app’s latest sample instead of an old snapshot. Weekly can still read 3% when that is the app’s current 7-day number. The session bar should move to the `fh` value from that same sample.

To replace that with a live Anthropic reading, renew the Claude Code sign-in (`claude auth login`) and confirm `claude auth status` reports the subscription you expect. Then open the AgentPulse panel again.

## Release bar for GitHub

Ship this folder as its own repository. Do not commit it from a parent folder that contains other personal projects.

- `./Scripts/test.sh` exits 0
- `./Scripts/bundle.sh` produces `AgentPulse.app`
- README still matches the panel: no claim of live Max detection, budget alerts, or multi-machine sync
- No `.env`, Keychain export, or transcript fixture copied from a personal machine
