import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var store: StateStore
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: store.currentTheme.isLight ? .contentBackground : .hudWindow)
            store.theme.bg.opacity(store.currentTheme.isLight ? 0.62 : 0.82)
            
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if store.activeViewMode == .dashboard {
                    DashboardView(store: store)
                } else {
                    SettingsView(store: store)
                }
            }
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(store.theme.accent.opacity(0.18))
                Image(systemName: store.statusSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(store.theme.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.agentFilter?.rawValue ?? "AgentPulse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(store.theme.textPrimary)
                HStack(alignment: .top, spacing: 6) {
                    PulseDot(color: Color(red: 0.45, green: 0.78, blue: 0.48))
                        .padding(.top, 3)
                    Text(store.subscriptionHeadline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                themeMenu
                iconButton(systemName: store.activeViewMode == .settings ? "chart.bar.fill" : "gearshape.fill") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.activeViewMode = (store.activeViewMode == .dashboard ? .settings : .dashboard)
                    }
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.theme.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(store.theme.cardBg))
                .help("Quit AgentPulse")
            }
        }
    }

    private var themeMenu: some View {
        ThemePaletteButton(
            symbolColor: store.theme.textPrimary,
            background: store.theme.cardBg,
            selection: store.currentTheme
        ) { preset in
            store.currentTheme = preset
        }
        .frame(width: 28, height: 28)
        .help("Choose theme")
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(store.theme.cardBg))
                .foregroundStyle(store.theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var store: StateStore

    private var groups: [ModelGroup] { store.modelGroups() }
    private var summary: (tokens: Int, cost: Double, active: Int, listed: Int) {
        store.summary(for: groups)
    }

    var body: some View {
        VStack(spacing: 14) {
            summaryCard
                .padding(.horizontal, 16)
            agentChips
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    plansSection
                    limitsSection
                    weekSection
                    modelsSection
                }
                .padding(.bottom, 18)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                summaryMetric(title: "Tokens", value: TokenFormat.string(for: summary.tokens))
                summaryDivider
                summaryMetric(title: "Est. cost", value: CostEstimate.summary(summary.cost))
                summaryDivider
                summaryMetric(title: "Active", value: "\(summary.active)")
            }
            Text("\(summary.listed) models with usage · counted from transcripts on this Mac")
                .font(.system(size: 10))
                .foregroundStyle(store.theme.textSecondary)
        }
        .padding(12)
        .background(cardBackground)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(store.theme.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(store.theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(store.theme.border)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    private var agentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                agentChip(title: "All", agent: nil, icon: "square.grid.2x2.fill")
                ForEach(AgentType.allCases) { agent in
                    agentChip(title: agent.shortLabel, agent: agent, icon: agent.iconName)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func agentChip(title: String, agent: AgentType?, icon: String) -> some View {
        let selected = store.agentFilter == agent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.select(agent: agent)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? store.theme.accent.opacity(0.22) : store.theme.cardBg)
            )
            .overlay(
                Capsule().stroke(selected ? store.theme.accent.opacity(0.7) : store.theme.border, lineWidth: 1)
            )
            .foregroundStyle(selected ? store.theme.textPrimary : store.theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var plansSection: some View {
        if !store.plansOnScreen.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Plan")
                ForEach(store.plansOnScreen) { plan in
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(plan.signedIn ? store.theme.accent.opacity(0.16) : store.theme.bg.opacity(0.4))
                            Image(systemName: plan.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(plan.signedIn ? store.theme.accent : store.theme.textSecondary)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(plan.product)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(store.theme.textSecondary)
                                Spacer(minLength: 8)
                                Text(store.headline(for: plan))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(plan.signedIn ? store.theme.textPrimary : store.theme.textSecondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text(store.detail(for: plan))
                                .font(.system(size: 10))
                                .foregroundStyle(store.theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(cardBackground)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        if !store.displayedLimits.isEmpty {
            limitsCard
        }
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Limits")
            VStack(spacing: 10) {
                ForEach(store.displayedLimits) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(store.theme.textPrimary)
                            Spacer()
                            Text(item.resetTimer)
                                .font(.system(size: 10))
                                .foregroundStyle(store.theme.textSecondary)
                            Text("\(item.percent)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(store.theme.textPrimary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        meter(fraction: Double(item.percent) / 100, height: 5)
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
            if !store.displayedLimitsNote.isEmpty {
                Text(store.displayedLimitsNote)
                    .font(.system(size: 10))
                    .foregroundStyle(store.theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("This week")
            Text("Tokens from Claude Code and Codex session files on this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(store.theme.textSecondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(store.tokensByDay) { item in
                    VStack(spacing: 6) {
                        Text(item.tokenString == "0" ? " " : compactToken(item.tokenString))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(store.theme.textSecondary)
                            .lineLimit(1)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(item.dayLabel == "Today" ? store.theme.accent : store.theme.barFill.opacity(0.85))
                            .frame(height: max(4, 64 * item.fraction))
                        Text(item.dayLabel == "Today" ? "Now" : item.dayLabel)
                            .font(.system(size: 9, weight: item.dayLabel == "Today" ? .bold : .medium))
                            .foregroundStyle(item.dayLabel == "Today" ? store.theme.textPrimary : store.theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 108, alignment: .bottom)
            .padding(12)
            .background(cardBackground)
        }
        .padding(.horizontal, 16)
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Models")
                Spacer()
                Text("\(summary.listed)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.theme.textSecondary)
            }
            .padding(.horizontal, 16)

            if groups.isEmpty {
                Text("No transcript usage for this view yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(store.theme.textSecondary)
                    .padding(.horizontal, 16)
            }
            ForEach(groups) { group in
                if groups.count > 1 {
                    Text(group.vendor.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(store.theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                VStack(spacing: 6) {
                    ForEach(group.rows) { row in
                        modelRow(row)
                    }
                }
                .padding(.horizontal, 16)
            }

            Text(LLMCatalog.priceFootnote)
                .font(.system(size: 9))
                .foregroundStyle(store.theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 2)
        }
    }

    private func modelRow(_ row: ModelUsageRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.theme.textPrimary)
                if row.model.id == store.cursorModelID {
                    tierPill("In Cursor")
                }
                tierPill(row.model.tier)
                Spacer(minLength: 8)
                Text(row.tokenLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.tokens > 0 ? store.theme.textPrimary : store.theme.textSecondary)
            }
            HStack {
                Text(row.model.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(store.theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.model.priceLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(store.theme.textSecondary)
                if !row.costLabel.isEmpty {
                    Text(row.costLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(store.theme.accent)
                }
            }
            meter(fraction: row.fraction, height: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBackground)
    }

    private func tierPill(_ tier: String) -> some View {
        Text(tier)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(store.theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(store.theme.bg.opacity(0.55)))
    }

    private func meter(fraction: Double, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(store.theme.bg.opacity(0.55))
                Capsule()
                    .fill(store.theme.barFill)
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(store.theme.textSecondary)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(store.theme.cardBg.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(store.theme.border.opacity(0.9), lineWidth: 1)
            )
    }

    private func compactToken(_ raw: String) -> String {
        raw.replacingOccurrences(of: ".0M", with: "M")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var store: StateStore
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(title: "Agents") {
                    VStack(spacing: 6) {
                        ToggleRow(title: "Claude Code", isOn: $store.claudeEnabled, store: store)
                        ToggleRow(title: "Codex", isOn: $store.codexEnabled, store: store)
                        ToggleRow(title: "Grok", isOn: $store.grokEnabled, store: store)
                    }
                }

                settingsCard(title: "General") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Refresh interval")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(store.theme.textPrimary)
                            Spacer()
                            HStack(spacing: 8) {
                                Button("-") { if store.refreshIntervalSeconds > 60 { store.refreshIntervalSeconds -= 60 } }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(store.theme.textPrimary)
                                Text("\(store.refreshIntervalSeconds)s")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(store.theme.textPrimary)
                                    .frame(minWidth: 36)
                                Button("+") { store.refreshIntervalSeconds += 60 }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(store.theme.textPrimary)
                            }
                        }

                        ToggleBox(
                            title: "Show percentage in bar",
                            subtitle: "The fullest limit, next to the icon.",
                            isOn: $store.showPercentageInBar,
                            store: store
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agent command")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(store.theme.textPrimary)
                            TextField("", text: $store.agentCommand)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(store.theme.bg.opacity(0.45)))
                                .foregroundStyle(store.theme.textPrimary)
                            Text("What a right click on the icon runs in Terminal.")
                                .font(.system(size: 10))
                                .foregroundStyle(store.theme.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Records folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(store.theme.textPrimary)
                            HStack {
                                Text(store.recordsFolder)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(store.theme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Choose...") {}
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(store.theme.border, lineWidth: 1))
                                    .foregroundStyle(store.theme.textPrimary)
                            }
                        }

                        ToggleBox(
                            title: "Launch at login",
                            subtitle: "",
                            isOn: $store.launchAtLogin,
                            store: store
                        )
                    }
                }

                settingsCard(title: "Sync") {
                    ToggleBox(
                        title: "Synced aggregation",
                        subtitle: "Write this machine’s usage snapshot and merge snapshots from other machines.",
                        isOn: $store.syncSettings.enabled,
                        store: store
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(store.theme.textSecondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(store.theme.cardBg.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(store.theme.border.opacity(0.9), lineWidth: 1)
                )
        )
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    @ObservedObject var store: StateStore
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.theme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}

struct ToggleBox: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @ObservedObject var store: StateStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.theme.textPrimary)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(store.theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PulseDot: View {
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let wave = (sin(context.date.timeIntervalSinceReferenceDate * 2.8) + 1) / 2
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(0.35 + 0.65 * wave)
        }
    }
}

struct ThemePaletteButton: NSViewRepresentable {
    var symbolColor: Color
    var background: Color
    var selection: ThemePreset
    var onSelect: (ThemePreset) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, selection: selection)
    }

    func makeNSView(context: Context) -> ThemePaletteControl {
        let button = ThemePaletteControl()
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        return button
    }

    func updateNSView(_ button: ThemePaletteControl, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.selection = selection
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.image = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "Choose theme")?
            .withSymbolConfiguration(configuration)
        button.contentTintColor = NSColor(symbolColor)
        button.layer?.backgroundColor = NSColor(background).cgColor
    }

    final class Coordinator: NSObject {
        var onSelect: (ThemePreset) -> Void
        var selection: ThemePreset

        init(onSelect: @escaping (ThemePreset) -> Void, selection: ThemePreset) {
            self.onSelect = onSelect
            self.selection = selection
        }

        @objc func openMenu(_ sender: NSButton) {
            let menu = NSMenu()
            for preset in ThemePreset.allCases {
                let item = NSMenuItem(title: preset.rawValue, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.rawValue
                item.state = preset == selection ? .on : .off
                menu.addItem(item)
            }
            NotificationCenter.default.post(name: .agentPulseHoldPopover, object: true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
            NotificationCenter.default.post(name: .agentPulseHoldPopover, object: false)
        }

        @objc func pick(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let preset = ThemePreset(rawValue: raw) else { return }
            onSelect(preset)
        }
    }
}

final class ThemePaletteControl: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        setButtonType(.momentaryChange)
        setAccessibilityLabel("Choose theme")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
