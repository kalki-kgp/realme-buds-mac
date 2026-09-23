import SwiftUI

@main
struct BudsApp: App {
    @StateObject private var buds = BudsModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView(buds: buds)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, now in
                    if now == .active { buds.refresh() }
                }
        }
    }
}

struct ContentView: View {
    @ObservedObject var buds: BudsModel

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        batteries
                        if buds.link == .connected {
                            CardSection(title: "Noise control") { NoiseControl(buds: buds) }
                            CardSection(title: "Sound") { sound }
                            CardSection(title: "More") { more }
                        } else {
                            offline
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                    .animation(Theme.spring, value: buds.link)
                }
                .refreshable { buds.refresh() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if buds.link == .connected {
                        Button {
                            buds.setRinging(!buds.ringing)
                        } label: {
                            Image(systemName: buds.ringing ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(buds.ringing ? "Stop ringing" : "Find buds")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "earbuds", hue: 0, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: buds.name).font(.title3.weight(.semibold))
                Text(verbatim: status).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private var status: String {
        switch buds.link {
        case .connected: return buds.firmware.map { "Firmware \($0)" } ?? "Connected"
        case .connecting: return "Connecting…"
        case .searching: return "Looking for your buds…"
        case .bluetoothOff: return "Bluetooth is off"
        case .busy:
            let when = buds.lastAnswer.map { " Last read \($0.formatted(.relative(presentation: .named)))." } ?? ""
            return "Another device has control.\(when)"
        }
    }

    private var batteries: some View {
        HStack(spacing: 0) {
            ForEach(Bud.allCases) { bud in
                BatteryRing(bud: bud, level: buds.battery[bud], placement: buds.placement[bud])
            }
        }
        .padding(.vertical, 18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .opacity(buds.link == .connected ? 1 : 0.6)
    }

    private var sound: some View {
        GlassCard {
            Row(title: "Equalizer") { IconTile(symbol: "slider.vertical.3", hue: 6) } control: {
                Menu {
                    Picker("Equalizer", selection: Binding(get: { buds.eq }, set: { if let v = $0 { buds.setEQ(v) } })) {
                        ForEach(EQPreset.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(buds.eq?.label ?? "—")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .foregroundStyle(.primary)
            }
            RowDivider()
            Row(title: "Game mode", detail: "Low-latency audio") { IconTile(symbol: "gamecontroller.fill", hue: 3) } control: {
                Toggle("", isOn: binding(0x06)).labelsHidden()
            }
            RowDivider()
            Row(title: "In-ear detection", detail: "Pause when a bud comes out") { IconTile(symbol: "ear", hue: 5) } control: {
                Toggle("", isOn: binding(0x04)).labelsHidden()
            }
        }
    }

    private var more: some View {
        GlassCard {
            NavigationLink { TouchControlsView(buds: buds) } label: { linkRow("Touch controls", "hand.tap.fill", 1) }
            RowDivider()
            NavigationLink { FeaturesView(buds: buds) } label: { linkRow("Features", "switch.2", 0) }
            RowDivider()
            NavigationLink { TouchLogView(buds: buds) } label: { linkRow("Touch log", "list.bullet.rectangle.fill", 3) }
        }
        .foregroundStyle(.primary)
    }

    private func linkRow(_ title: String, _ symbol: String, _ hue: Int) -> some View {
        Row(title: title) { IconTile(symbol: symbol, hue: hue) } control: {
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private var offline: some View {
        VStack(spacing: 12) {
            Image(systemName: buds.link == .busy ? "laptopcomputer" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: buds.link == .searching || buds.link == .connecting)
            Text(verbatim: offlineMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if buds.link == .busy {
                Button("Try again") { buds.refresh() }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var offlineMessage: String {
        switch buds.link {
        case .busy: return "Quit Buds on your Mac or close realme Link, then try again. The buds answer one app at a time."
        case .bluetoothOff: return "Turn on Bluetooth to reach your buds."
        default: return "Open the case near your iPhone."
        }
    }

    private func binding(_ id: UInt8) -> Binding<Bool> {
        Binding(get: { buds.features[id] ?? false }, set: { buds.setFeature(id, $0) })
    }
}

struct NoiseControl: View {
    @ObservedObject var buds: BudsModel
    private enum Mode: Hashable { case off, transparency, anc }

    var body: some View {
        VStack(spacing: 10) {
            TileSegmented(options: [(Mode.off, "Off", "circle.slash"),
                                    (.transparency, "Transparency", "ear.and.waveform"),
                                    (.anc, "Noise cancelling", "waveform.slash")],
                          selection: mode, tall: true) { picked in
                switch picked {
                case .off: buds.setNoiseMode(.off)
                case .transparency: buds.setNoiseMode(.transparency)
                case .anc:
                    if case .anc = buds.noiseMode { return }
                    buds.setNoiseMode(.anc(.smart))
                }
            }
            if case .anc(let level) = buds.noiseMode {
                TileSegmented(options: ANCLevel.allCases.map { ($0, $0.label, $0 == .smart ? "sparkles" : "cellularbars") },
                              selection: level) { buds.setNoiseMode(.anc($0)) }
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(Theme.spring, value: buds.noiseMode)
    }

    private var mode: Mode? {
        switch buds.noiseMode { case .off: .off; case .transparency: .transparency; case .anc: .anc; case nil: nil }
    }
}

struct TouchControlsView: View {
    @ObservedObject var buds: BudsModel

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(spacing: 22) {
                    ForEach([Bud.left, .right]) { bud in
                        CardSection(title: "\(bud.label) bud", trailing: AnyView(
                            Button("Turn all off") {
                                buds.setGesture(.none, for: Gesture.allCases.map { GestureSlot(bud: bud, gesture: $0) })
                            }
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.glass)
                        )) {
                            GlassCard {
                                ForEach(Array(Gesture.configurable.enumerated()), id: \.element) { i, gesture in
                                    if i > 0 { RowDivider() }
                                    Row(title: gesture.label) {
                                        IconTile(symbol: symbol(gesture), hue: bud == .left ? 5 : 3)
                                    } control: {
                                        picker(bud, gesture)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Touch controls")
    }

    private func picker(_ bud: Bud, _ gesture: Gesture) -> some View {
        let slot = GestureSlot(bud: bud, gesture: gesture)
        return Menu {
            ForEach(gesture.choices, id: \.self) { action in
                Button {
                    buds.setGesture(action, for: [slot])
                } label: {
                    if buds.gestures[slot] == action { Label(action.label, systemImage: "checkmark") } else { Text(action.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(buds.gestures[slot]?.label ?? "—")
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .foregroundStyle(.primary)
    }

    private func symbol(_ g: Gesture) -> String {
        switch g { case .double: "2.circle"; case .triple: "3.circle"; case .hold: "hand.point.up.left.fill"; default: "circle" }
    }
}

struct FeaturesView: View {
    @ObservedObject var buds: BudsModel

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                GlassCard {
                    ForEach(Array(Feature.all.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { RowDivider() }
                        Row(title: f.title, detail: f.detail) { IconTile(symbol: f.symbol, hue: f.hue) } control: {
                            Toggle("", isOn: Binding(get: { buds.features[f.id] ?? false }, set: { buds.setFeature(f.id, $0) }))
                                .labelsHidden()
                        }
                        .opacity(buds.features[f.id] == nil ? 0.5 : 1)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Features")
    }
}

struct TouchLogView: View {
    @ObservedObject var buds: BudsModel

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Touches and in/out-of-ear changes, as the buds report them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                    GlassCard {
                        if buds.events.isEmpty {
                            Text(buds.link == .connected ? "Nothing yet. Tap a bud to see it here." : "Waiting for the buds…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(16)
                        } else {
                            ForEach(Array(buds.events.enumerated()), id: \.element.id) { i, e in
                                if i > 0 { RowDivider(inset: 48) }
                                EventRow(event: e)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Touch log")
        .toolbar {
            if !buds.events.isEmpty {
                Button("Clear") { buds.clearEvents() }
            }
        }
    }
}
