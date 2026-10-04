import SwiftUI

/// Supported AI Coding Agents
enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claude = "Claude Code"
    case grok = "Grok"
    case codex = "Codex"
    case gemini = "Gemini CLI"
    case copilot = "Copilot"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .claude: return "sparkles"
        case .grok: return "brain"
        case .codex: return "terminal.fill"
        case .gemini: return "bolt.horizontal.fill"
        case .copilot: return "cpu.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        }
    }
}

/// Color Theme Presets
enum ThemePreset: String, CaseIterable, Identifiable, Codable {
    case catppuccin = "Catppuccin"
    case catppuccinLatte = "Catppuccin Latte"
    case ethereal = "Ethereal"
    case everforest = "Everforest"
    case flexokiLight = "Flexoki Light"
    case gruvbox = "Gruvbox"
    case hackerman = "Hackerman"
    case kanagawa = "Kanagawa"
    
    var id: String { rawValue }
    
    var isLight: Bool {
        self == .catppuccinLatte || self == .flexokiLight
    }
    
    var themeColors: ThemeColors {
        switch self {
        case .catppuccin:
            return ThemeColors(
                bg: Color(red: 0.12, green: 0.12, blue: 0.18),
                cardBg: Color(red: 0.18, green: 0.18, blue: 0.24),
                textPrimary: Color(red: 0.85, green: 0.88, blue: 0.95),
                textSecondary: Color(red: 0.55, green: 0.60, blue: 0.70),
                accent: Color(red: 0.85, green: 0.65, blue: 0.55),
                barFill: Color(red: 0.65, green: 0.60, blue: 0.50),
                border: Color(red: 0.25, green: 0.25, blue: 0.35)
            )
        case .catppuccinLatte:
            return ThemeColors(
                bg: Color(red: 0.95, green: 0.94, blue: 0.90),
                cardBg: Color(red: 0.90, green: 0.88, blue: 0.82),
                textPrimary: Color(red: 0.20, green: 0.20, blue: 0.22),
                textSecondary: Color(red: 0.50, green: 0.50, blue: 0.48),
                accent: Color(red: 0.70, green: 0.45, blue: 0.35),
                barFill: Color(red: 0.35, green: 0.35, blue: 0.32),
                border: Color(red: 0.80, green: 0.78, blue: 0.72)
            )
        case .everforest:
            return ThemeColors(
                bg: Color(red: 0.15, green: 0.18, blue: 0.17),
                cardBg: Color(red: 0.20, green: 0.24, blue: 0.22),
                textPrimary: Color(red: 0.82, green: 0.85, blue: 0.78),
                textSecondary: Color(red: 0.55, green: 0.60, blue: 0.55),
                accent: Color(red: 0.65, green: 0.75, blue: 0.55),
                barFill: Color(red: 0.60, green: 0.65, blue: 0.52),
                border: Color(red: 0.28, green: 0.32, blue: 0.29)
            )
        case .gruvbox:
            return ThemeColors(
                bg: Color(red: 0.16, green: 0.16, blue: 0.15),
                cardBg: Color(red: 0.24, green: 0.22, blue: 0.20),
                textPrimary: Color(red: 0.92, green: 0.86, blue: 0.70),
                textSecondary: Color(red: 0.65, green: 0.60, blue: 0.50),
                accent: Color(red: 0.98, green: 0.74, blue: 0.18),
                barFill: Color(red: 0.85, green: 0.60, blue: 0.25),
                border: Color(red: 0.32, green: 0.30, blue: 0.26)
            )
        case .hackerman:
            return ThemeColors(
                bg: Color(red: 0.05, green: 0.08, blue: 0.05),
                cardBg: Color(red: 0.08, green: 0.14, blue: 0.08),
                textPrimary: Color(red: 0.20, green: 0.95, blue: 0.35),
                textSecondary: Color(red: 0.15, green: 0.65, blue: 0.25),
                accent: Color(red: 0.30, green: 1.00, blue: 0.45),
                barFill: Color(red: 0.15, green: 0.75, blue: 0.30),
                border: Color(red: 0.15, green: 0.35, blue: 0.18)
            )
        case .kanagawa:
            return ThemeColors(
                bg: Color(red: 0.12, green: 0.12, blue: 0.15),
                cardBg: Color(red: 0.16, green: 0.16, blue: 0.20),
                textPrimary: Color(red: 0.85, green: 0.84, blue: 0.75),
                textSecondary: Color(red: 0.55, green: 0.55, blue: 0.60),
                accent: Color(red: 0.45, green: 0.60, blue: 0.70),
                barFill: Color(red: 0.75, green: 0.60, blue: 0.45),
                border: Color(red: 0.22, green: 0.22, blue: 0.28)
            )
        case .flexokiLight:
            return ThemeColors(
                bg: Color(red: 0.98, green: 0.96, blue: 0.92),
                cardBg: Color(red: 0.92, green: 0.90, blue: 0.84),
                textPrimary: Color(red: 0.10, green: 0.10, blue: 0.10),
                textSecondary: Color(red: 0.45, green: 0.45, blue: 0.42),
                accent: Color(red: 0.80, green: 0.40, blue: 0.20),
                barFill: Color(red: 0.30, green: 0.30, blue: 0.28),
                border: Color(red: 0.82, green: 0.80, blue: 0.74)
            )
        case .ethereal:
            return ThemeColors(
                bg: Color(red: 0.10, green: 0.12, blue: 0.16),
                cardBg: Color(red: 0.15, green: 0.18, blue: 0.24),
                textPrimary: Color(red: 0.90, green: 0.92, blue: 0.98),
                textSecondary: Color(red: 0.55, green: 0.60, blue: 0.72),
                accent: Color(red: 0.50, green: 0.75, blue: 0.95),
                barFill: Color(red: 0.40, green: 0.60, blue: 0.80),
                border: Color(red: 0.22, green: 0.26, blue: 0.34)
            )
        }
    }
}

struct ThemeColors {
    let bg: Color
    let cardBg: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let barFill: Color
    let border: Color
}

/// Rate Limit Breakdown Item
struct RateLimitItem: Identifiable, Codable {
    var id: String { title }
    let title: String
    let percent: Int
    let resetTimer: String // e.g. "Resets in 25m", "Resets in 2d 23h"
}

/// Token Usage by Day
struct DayUsageItem: Identifiable, Codable {
    var id: String { dayLabel }
    let dayLabel: String
    let tokenString: String
    let fraction: Double
}

/// Token Usage by Model
struct ModelUsageItem: Identifiable, Codable {
    var id: String { modelName }
    let modelName: String
    let tokenString: String
    let fraction: Double
}

/// Sync Configuration Model
struct SyncSettings: Codable {
    var enabled: Bool = false
    var syncFolder: String = ""
    var snapshotFileName: String = "sams-macbook-pro.json"
    var deviceId: String = "sams-macbook-pro"
}
