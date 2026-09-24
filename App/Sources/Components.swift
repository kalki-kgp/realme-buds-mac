import SwiftUI

/// The rounded gradient tile Droppy's settings put beside a row or a sidebar item.
struct IconTile: View {
    let symbol: String
    let hue: Int
    var size: CGFloat = 26

    var body: some View {
        let color = Chrome.tileHues[hue % Chrome.tileHues.count]
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}

/// Equal cells in one card with a highlight that slides between them — the
/// "Menu bar icon | Dock icon | Launch at login" strip from Droppy's General page.
struct TileSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String, symbol: String)]
    let selection: Value?
    var vertical = false
    let onSelect: (Value) -> Void

    @Namespace private var highlight
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 && selection != option.value && selection != options[index - 1].value {
                    Rectangle().fill(Chrome.overlay(0.1)).frame(width: 1, height: 16)
                } else if index > 0 {
                    Color.clear.frame(width: 1, height: 16)
                }
                cell(option)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Chrome.overlay(0.05)))
        .animation(Chrome.panelSlide, value: selection)
    }

    @ViewBuilder
    private func cell(_ option: (value: Value, title: String, symbol: String)) -> some View {
        let isSelected = option.value == selection
        Button { onSelect(option.value) } label: {
            Group {
                if vertical {
                    VStack(spacing: 5) {
                        Image(systemName: option.symbol).font(.system(size: 15, weight: .medium))
                        Text(verbatim: option.title).font(.system(size: 11, weight: .medium))
                    }
                    .frame(height: 50)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .medium))
                        Text(verbatim: option.title).font(.system(size: 12, weight: .medium))
                    }
                    .frame(height: 30)
                }
            }
            .lineLimit(1)
            .foregroundStyle(Chrome.primaryText.opacity(isSelected ? 1 : 0.72))
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Chrome.overlay(0.13))
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                } else if hovered == option.value {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Chrome.overlay(0.05))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Chrome.hover) { hovered = h ? option.value : nil } }
    }
}

/// A battery ring with the bud's glyph inside and the level underneath.
struct BatteryRing: View {
    let bud: Bud
    let level: BatteryLevel?
    let placement: Placement?

    var body: some View {
        let fraction = Double(level?.percent ?? 0) / 100
        let color: Color = (level?.charging ?? false) ? Chrome.success
            : fraction <= 0.2 && level?.percent != nil ? Chrome.danger : Chrome.primaryText.opacity(0.85)
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(Chrome.overlay(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.5), value: fraction)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Chrome.primaryText.opacity(level?.percent == nil ? 0.35 : 0.9))
                if level?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Chrome.success)
                        .offset(y: 16)
                }
            }
            .frame(width: 50, height: 50)
            VStack(spacing: 1) {
                Text(verbatim: level?.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(verbatim: subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Chrome.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var symbol: String {
        switch bud { case .left: "airpod.left"; case .right: "airpod.right"; case .enclosure: "earbuds.case" }
    }

    private var subtitle: String {
        if bud == .enclosure { return level?.percent == nil ? "Closed" : "Case" }
        return "\(bud.label) · \(placement?.label ?? "—")"
    }
}

struct EventRow: View {
    let event: TouchEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.isTouch ? Chrome.warning : Chrome.secondaryText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title).font(.system(size: 12.5, weight: .medium))
                Text(verbatim: event.detail).font(.system(size: 11)).foregroundStyle(Chrome.secondaryText)
            }
            Spacer()
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .transition(.softAppear)
    }
}

/// The devices the buds remember. Two can be connected at once; connecting a third
/// asks which of the two to drop. This Mac can't be dropped from here, since the
/// app talks to the buds through it.
struct DevicesCard: View {
    @ObservedObject var buds: BudsClient

    var body: some View {
        ChromeCard {
            if buds.devices.isEmpty {
                ChromeRow(title: "Reading the list…") { ProgressView().controlSize(.small) }
            }
            ForEach(Array(buds.devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { ChromeRowDivider(inset: 50) }
                ChromeRow(title: device.name, detail: detail(device)) {
                    IconTile(symbol: "laptopcomputer.and.iphone", hue: device.isConnected ? 5 : 8)
                } control: {
                    control(device)
                }
            }
        }
    }

    private var connected: [PairedDevice] { buds.devices.filter(\.isConnected) }

    private func detail(_ device: PairedDevice) -> String {
        if buds.switching.contains(device.id) { return device.isConnected ? "Disconnecting…" : "Connecting…" }
        if device.isThisDevice { return "This Mac" }
        return device.isConnected ? "Connected" : "Not connected"
    }

    @ViewBuilder
    private func control(_ device: PairedDevice) -> some View {
        if buds.switching.contains(device.id) {
            ProgressView().controlSize(.small)
        } else if device.isThisDevice {
            EmptyView()
        } else if device.isConnected {
            ChromeTextButton(symbol: "xmark", title: "Disconnect", help: "Disconnect \(device.name) from the buds") {
                buds.disconnect(device)
            }
        } else if connected.count < 2 {
            ChromeTextButton(symbol: "link", title: "Connect", help: "Connect \(device.name) to the buds") {
                buds.connect(device)
            }
        } else {
            let droppable = connected.filter { !$0.isThisDevice }
            ChromeTextMenu(symbol: "arrow.left.arrow.right", title: "Switch", help: "Swap \(device.name) in for another device") {
                PopoverSectionHeader("Disconnect to make room")
                ForEach(droppable) { other in
                    PopoverItem(other.name) { buds.connect(device, replacing: other) }
                }
            }
        }
    }
}

/// Noise control: three modes, and the four ANC strengths once ANC is on.
struct NoiseControlCard: View {
    @ObservedObject var buds: BudsClient

    private enum Mode: Hashable { case off, transparency, anc }

    var body: some View {
        VStack(spacing: 8) {
            TileSegmented(
                options: [(Mode.off, "Off", "circle.slash"),
                          (.transparency, "Transparency", "ear.and.waveform"),
                          (.anc, "Noise cancelling", "waveform.slash")],
                selection: mode,
                vertical: true
            ) { picked in
                switch picked {
                case .off: buds.setNoiseMode(.off)
                case .transparency: buds.setNoiseMode(.transparency)
                case .anc:
                    if case .anc = buds.noiseMode { return }
                    buds.setNoiseMode(.anc(.smart))
                }
            }
            if case .anc(let level) = buds.noiseMode {
                TileSegmented(options: ANCLevel.allCases.map { ($0, $0.label, levelSymbol($0)) }, selection: level) {
                    buds.setNoiseMode(.anc($0))
                }
                .transition(.softAppear)
            }
        }
        .animation(Chrome.panelSlide, value: buds.noiseMode)
    }

    private var mode: Mode? {
        switch buds.noiseMode {
        case .off: .off; case .transparency: .transparency; case .anc: .anc; case nil: nil
        }
    }

    private func levelSymbol(_ l: ANCLevel) -> String {
        switch l { case .smart: "sparkles"; case .mild: "cellularbars"; case .moderate: "cellularbars"; case .max: "cellularbars" }
    }
}

extension BudsClient {
    func binding(for feature: UInt8) -> Binding<Bool> {
        Binding(get: { self.features[feature] ?? false }, set: { self.setFeature(feature, $0) })
    }

    var eqBinding: Binding<EQPreset?> {
        Binding(get: { self.eq }, set: { if let v = $0 { self.setEQ(v) } })
    }
}
