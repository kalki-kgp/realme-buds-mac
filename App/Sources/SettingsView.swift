import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, devices, sound, touch, features, log, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"; case .devices: "Devices"; case .sound: "Sound"; case .touch: "Touch controls"
        case .features: "Features"; case .log: "Touch log"; case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"; case .devices: "laptopcomputer.and.iphone"; case .sound: "waveform"; case .touch: "hand.tap.fill"
        case .features: "switch.2"; case .log: "list.bullet.rectangle.fill"; case .about: "info"
        }
    }
    var hue: Int {
        switch self { case .general: 8; case .devices: 5; case .sound: 6; case .touch: 1; case .features: 0; case .log: 3; case .about: 4 }
    }
    /// Sidebar groups, the way Droppy spaces its sections.
    static let groups: [[SettingsPage]] = [[.general, .devices], [.sound, .touch, .features], [.log], [.about]]
}

final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .general
}

struct SettingsView: View {
    @ObservedObject var buds: BudsClient
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 34)   // traffic lights
            ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                VStack(spacing: 2) {
                    ForEach(group) { page in SidebarItem(page: page, isSelected: nav.page == page) { nav.page = page } }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 190)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
                Text(verbatim: nav.page.title)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 4)
                page
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .id(nav.page)
            .transition(.softAppear)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.22))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(10)
        .animation(.smooth(duration: 0.25), value: nav.page)
    }

    @ViewBuilder private var page: some View {
        if buds.link != .connected && nav.page != .about && nav.page != .log {
            ChromeCard {
                ChromeRow(title: "Buds not connected", detail: nil) {
                    IconTile(symbol: "earbuds.case", hue: 8)
                } control: {
                    if buds.link == .disconnected {
                        ChromeTextButton(symbol: "link", title: "Connect", help: "Connect") { buds.connectAudio() }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } else {
            switch nav.page {
            case .general: GeneralPage(buds: buds)
            case .devices: DevicesPage(buds: buds)
            case .sound: SoundPage(buds: buds)
            case .touch: TouchPage(buds: buds)
            case .features: FeaturesPage(buds: buds)
            case .log: LogPage(buds: buds)
            case .about: AboutPage()
            }
        }
    }
}

private struct SidebarItem: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconTile(symbol: page.symbol, hue: page.hue, size: 20)
                Text(verbatim: page.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Chrome.primaryText.opacity(isSelected ? 1 : 0.9))
                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Chrome.overlay(0.12) : isHovering ? Chrome.overlay(0.06) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Chrome.hover) { isHovering = h } }
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Bud.allCases) { BatteryRing(bud: $0, level: buds.battery[$0], placement: buds.placement[$0]) }
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Chrome.cardCornerRadius, style: .continuous).fill(Chrome.overlay(0.05)))

        ChromeSection(title: "Device") {
            ChromeCard {
                ChromeRow(title: buds.deviceName, detail: "Firmware \(buds.firmware ?? "—")") {
                    IconTile(symbol: "earbuds", hue: 0)
                } control: {
                    ChromeTextButton(symbol: "arrow.clockwise", title: "Refresh", help: "Read everything from the buds again") {
                        buds.refresh()
                    }
                }
            }
        }

        ChromeSection(title: "Find") {
            ChromeCard {
                ChromeRow(title: "Find buds", detail: "Loud. Take them out first.") {
                    IconTile(symbol: "speaker.wave.3.fill", hue: 1)
                } control: {
                    ChromeTextButton(symbol: buds.ringing ? "stop.fill" : "play.fill",
                                     title: buds.ringing ? "Stop" : "Ring", help: "Ring the buds") {
                        buds.setRinging(!buds.ringing)
                    }
                }
            }
        }
    }
}

private struct DevicesPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        ChromeCard {
            ChromeRow(title: "Dual connection", detail: "Two devices at a time") {
                IconTile(symbol: "rectangle.2.swap", hue: 0)
            } control: {
                SettingsSwitch(isOn: buds.binding(for: 0x11))
            }
        }
        ChromeSection(title: "Remembered", trailing: AnyView(
            ChromeTextButton(symbol: "arrow.clockwise", title: "Refresh", help: "Ask the buds for the list again") {
                buds.refresh()
            }
        )) {
            DevicesCard(buds: buds)
        }
    }
}

private struct SoundPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        ChromeSection(title: "Noise control") { NoiseControlCard(buds: buds) }
        ChromeSection(title: "Equalizer") {
            TileSegmented(
                options: EQPreset.allCases.map { ($0, $0.label, eqSymbol($0)) },
                selection: buds.eq,
                vertical: true
            ) { buds.setEQ($0) }
        }
        ChromeSection(title: "Enhancements") {
            ChromeCard {
                ForEach(Array(Feature.all.filter { [0x1B, 0x1D, 0x09, 0x18].contains($0.id) }.enumerated()), id: \.element.id) { i, f in
                    if i > 0 { ChromeRowDivider(inset: 50) }
                    FeatureRow(buds: buds, feature: f)
                }
            }
        }
    }

    private func eqSymbol(_ p: EQPreset) -> String {
        switch p { case .original: "music.note"; case .deepBass: "speaker.wave.3"; case .serenade: "music.mic"; case .clearBass: "waveform.path" }
    }
}

private struct TouchPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        ForEach([Bud.left, .right]) { bud in
            ChromeSection(title: "\(bud.label) bud", trailing: AnyView(
                ChromeTextButton(symbol: "hand.raised.slash", title: "Turn all off", help: "Set every \(bud.label.lowercased()) gesture to None") {
                    buds.setGesture(.none, for: Gesture.allCases.map { GestureSlot(bud: bud, gesture: $0) })
                }
            )) {
                ChromeCard {
                    ForEach(Array(Gesture.configurable.enumerated()), id: \.element) { i, gesture in
                        if i > 0 { ChromeRowDivider(inset: 50) }
                        ChromeRow(title: gesture.label) {
                            IconTile(symbol: symbol(gesture), hue: bud == .left ? 5 : 3)
                        } control: {
                            GlassPickerButton(
                                options: gesture.choices.map { (Optional($0), $0.label) },
                                selection: Binding(
                                    get: { buds.gestures[GestureSlot(bud: bud, gesture: gesture)] },
                                    set: { if let a = $0 { buds.setGesture(a, for: [GestureSlot(bud: bud, gesture: gesture)]) } }
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ g: Gesture) -> String {
        switch g { case .double: "2.circle"; case .triple: "3.circle"; case .hold: "hand.point.up.left.fill"; default: "circle" }
    }
}

private struct FeaturesPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        ChromeCard {
            ForEach(Array(Feature.all.enumerated()), id: \.element.id) { i, f in
                if i > 0 { ChromeRowDivider(inset: 50) }
                FeatureRow(buds: buds, feature: f)
            }
        }
    }
}

private struct FeatureRow: View {
    @ObservedObject var buds: BudsClient
    let feature: Feature

    var body: some View {
        ChromeRow(title: feature.title, detail: feature.detail) {
            IconTile(symbol: feature.symbol, hue: feature.hue)
        } control: {
            SettingsSwitch(isOn: buds.binding(for: feature.id))
        }
        .opacity(buds.features[feature.id] == nil ? 0.5 : 1)
    }
}

private struct LogPage: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        Text("Touches and in/out-of-ear changes, as the buds report them.")
            .font(.system(size: 12))
            .foregroundStyle(Chrome.secondaryText)
            .padding(.horizontal, 4)

        ChromeSection(title: "Events", trailing: buds.events.isEmpty ? nil : AnyView(
            ChromeTextButton(symbol: "trash", title: "Clear", help: "Clear the log") { buds.clearEvents() }
        )) {
            ChromeCard {
                if buds.events.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.tap").foregroundStyle(Chrome.secondaryText)
                        Text(buds.link == .connected ? "Nothing yet. Tap a bud to see it here." : "Waiting for the buds…")
                            .font(.system(size: 12.5)).foregroundStyle(Chrome.secondaryText)
                    }
                    .padding(14)
                } else {
                    ForEach(Array(buds.events.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { ChromeRowDivider(inset: 40) }
                        EventRow(event: e)
                    }
                }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        ChromeCard {
            ChromeRow(title: "Buds", detail: "Version 1.0") {
                IconTile(symbol: "earbuds", hue: 0, size: 32)
            } control: { EmptyView() }
        }
        ChromeSection(title: "Credits") {
            ChromeCard {
                ChromeRow(title: "Protocol", detail: "maniacx/BudsLink and anikket-b/Realme-TWS-Mac-Controller") { EmptyView() }
                ChromeRowDivider()
                ChromeRow(title: "Design system", detail: "Chrome components from Droppy Code, MIT, © T3 Tools Inc. & Jordy Spruit") { EmptyView() }
            }
        }
    }
}
