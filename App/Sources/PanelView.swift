import SwiftUI

/// What the menu bar icon opens.
struct PanelView: View {
    @ObservedObject var buds: BudsClient
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if buds.link == .connected {
                batteries
                ChromeSection(title: "Noise control") { NoiseControlCard(buds: buds) }
                quickSettings
                if let latest = buds.events.first(where: \.isTouch) {
                    lastTouch(latest)
                }
            } else {
                offline
            }
            footer
        }
        .padding(16)
        .frame(width: 356)
        .animation(Chrome.panelSlide, value: buds.link)
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "earbuds", hue: 0, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: buds.deviceName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: status)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
            Spacer()
            ChromeCircleButton(symbol: "gearshape", help: "Settings", action: openSettings)
        }
    }

    private var status: String {
        switch buds.link {
        case .connected: buds.firmware.map { "Firmware \($0)" } ?? "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not connected"
        case .noDevice: "No buds paired"
        }
    }

    private var batteries: some View {
        HStack(spacing: 0) {
            ForEach(Bud.allCases) { bud in
                BatteryRing(bud: bud, level: buds.battery[bud], placement: buds.placement[bud])
            }
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Chrome.cardCornerRadius, style: .continuous).fill(Chrome.overlay(0.05)))
    }

    private var quickSettings: some View {
        ChromeSection(title: "Sound") {
            ChromeCard {
                ChromeRow(title: "Equalizer") {
                    IconTile(symbol: "slider.vertical.3", hue: 6)
                } control: {
                    GlassPickerButton(options: EQPreset.allCases.map { (Optional($0), $0.label) }, selection: buds.eqBinding)
                }
                ChromeRowDivider(inset: 50)
                ChromeRow(title: "Game mode", detail: "Low-latency audio") {
                    IconTile(symbol: "gamecontroller.fill", hue: 3)
                } control: {
                    SettingsSwitch(isOn: buds.binding(for: 0x06))
                }
                ChromeRowDivider(inset: 50)
                ChromeRow(title: "In-ear detection", detail: "Pause when a bud comes out") {
                    IconTile(symbol: "ear", hue: 5)
                } control: {
                    SettingsSwitch(isOn: buds.binding(for: 0x04))
                }
            }
        }
    }

    private func lastTouch(_ event: TouchEvent) -> some View {
        Button(action: openSettings) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").foregroundStyle(Chrome.warning)
                Text(verbatim: "Last touch: \(event.title)").lineLimit(1)
                Spacer()
                Text(event.date, style: .relative).foregroundStyle(Chrome.secondaryText)
                Image(systemName: "chevron.right").font(Chrome.chevronFont).foregroundStyle(Chrome.secondaryText)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule(style: .continuous).fill(Chrome.overlay(0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.softAppear)
    }

    private var offline: some View {
        VStack(spacing: 12) {
            Image(systemName: buds.link == .connecting ? "antenna.radiowaves.left.and.right" : "earbuds.case")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Chrome.secondaryText)
                .symbolEffect(.pulse, isActive: buds.link == .connecting)
            Text(verbatim: message)
                .font(.system(size: 12.5))
                .foregroundStyle(Chrome.secondaryText)
                .multilineTextAlignment(.center)
            if buds.link == .disconnected {
                ChromeTextButton(symbol: "link", title: "Connect", help: "Connect the buds to this Mac") {
                    buds.connectAudio()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: Chrome.cardCornerRadius, style: .continuous).fill(Chrome.overlay(0.05)))
    }

    private var message: String {
        if let error = buds.lastError, buds.link != .connecting { return error }
        switch buds.link {
        case .connecting: return "Opening the control channel…"
        case .disconnected: return "Open the case near your Mac, or connect below."
        default: return "Pair your realme buds in Bluetooth settings first."
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if buds.link == .connected {
                ChromeTextButton(symbol: buds.ringing ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                 title: buds.ringing ? "Stop" : "Find buds",
                                 help: "Play a loud tone from the buds. Take them out first.") {
                    buds.setRinging(!buds.ringing)
                }
            }
            Spacer()
            ChromeCircleButton(symbol: "power", help: "Quit") { NSApp.terminate(nil) }
        }
    }
}
