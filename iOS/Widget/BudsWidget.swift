// Home Screen and Lock Screen widgets. They only read what the app last saved to the app group;
// the app keeps the BLE link and asks WidgetKit to redraw when something visible changes.

import SwiftUI
import WidgetKit

struct BudsEntry: TimelineEntry {
    let date: Date
    let snapshot: BudsSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BudsEntry { BudsEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (BudsEntry) -> Void) {
        completion(BudsEntry(date: .now, snapshot: context.isPreview ? SharedStore.load() ?? .placeholder : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudsEntry>) -> Void) {
        let entry = BudsEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

@main
struct BudsWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudsBattery", provider: Provider()) { entry in
            BatteryWidgetView(entry: entry)
                .widgetURL(URL(string: "buds://open"))
        }
        .configurationDisplayName("Buds")
        .description("Battery for each bud and the case.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BatteryWidgetView: View {
    let entry: BudsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(s: s)
                case .systemMedium: MediumView(s: s)
                case .accessoryCircular: CircularView(s: s)
                case .accessoryRectangular: RectangularView(s: s)
                case .accessoryInline: InlineView(s: s)
                default: SmallView(s: s)
                }
            } else {
                EmptyStateView()
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }
}

// MARK: - Background

/// Deep and a little translucent-looking in the full-colour style. In the clear and tinted Home
/// Screen styles iOS 26 swaps this for its own Liquid Glass and renders the content in one tint.
struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.42), Color(red: 0.36, green: 0.16, blue: 0.30)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.55, blue: 0.3).opacity(0.35))
                    .frame(width: 140)
                    .blur(radius: 40)
                    .offset(x: 40, y: -50)
            }
    }
}

// MARK: - Pieces

struct Ring: View {
    let bud: Bud
    let reading: BatteryReading?
    var size: CGFloat
    var line: CGFloat = 5
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let fraction = Double(reading?.percent ?? 0) / 100
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: bud.symbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(.white.opacity(reading?.percent == nil ? 0.35 : 0.95))
            if reading?.charging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(mode == .fullColor ? .green : .white)
                    .offset(y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
    }

    private var tint: Color {
        guard mode == .fullColor else { return .white }
        if reading?.charging == true { return .green }
        if let p = reading?.percent, p <= 20 { return .red }
        return .white
    }
}

struct Percent: View {
    let reading: BatteryReading?
    var font: Font = .system(size: 15, weight: .semibold, design: .rounded)

    var body: some View {
        Text(verbatim: reading?.percent.map { "\($0)%" } ?? "—")
            .font(font.monospacedDigit())
            .foregroundStyle(.white)
    }
}

/// "2 min ago" once the reading is older than a few minutes or the buds stopped answering.
struct Freshness: View {
    let s: BudsSnapshot

    var body: some View {
        if !s.live || Date.now.timeIntervalSince(s.updated) > 5 * 60 {
            Text(s.updated, style: .relative)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                + Text(" ago").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Home Screen

struct SmallView: View {
    let s: BudsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "earbuds").font(.system(size: 12, weight: .semibold))
                Text("Buds").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let mode = s.noiseMode {
                    Image(systemName: mode.symbol).font(.system(size: 12, weight: .semibold)).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                ForEach([Bud.left, .right]) { bud in
                    VStack(spacing: 5) {
                        Ring(bud: bud, reading: s.battery[bud], size: 50)
                        Percent(reading: s.battery[bud])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Image(systemName: "earbuds.case").font(.system(size: 11))
                Text(verbatim: s.battery[.enclosure]?.percent.map { "\($0)%" } ?? "Closed")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Spacer()
                Freshness(s: s)
            }
            .foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct MediumView: View {
    let s: BudsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "earbuds").font(.system(size: 13, weight: .semibold))
                Text(verbatim: s.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if let mode = s.noiseMode {
                    Label(mode.label, systemImage: mode.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            HStack(spacing: 0) {
                ForEach(Bud.allCases) { bud in
                    VStack(spacing: 6) {
                        Ring(bud: bud, reading: s.battery[bud], size: 56)
                        Percent(reading: s.battery[bud], font: .system(size: 16, weight: .semibold, design: .rounded))
                        Text(verbatim: bud == .enclosure ? "Case" : "\(bud.label) · \(s.placement[bud]?.label ?? "—")")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Spacer()
                Freshness(s: s)
            }
            .frame(height: 12)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "earbuds").font(.system(size: 26, weight: .light))
            Text("Open Buds once to connect")
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.8))
    }
}

// MARK: - Lock Screen

struct CircularView: View {
    let s: BudsSnapshot

    var body: some View {
        Gauge(value: Double(s.budsPercent ?? 0), in: 0...100) {
            Image(systemName: "earbuds")
        } currentValueLabel: {
            Text(verbatim: s.budsPercent.map(String.init) ?? "—")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

struct RectangularView: View {
    let s: BudsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Buds", systemImage: "earbuds").font(.headline).widgetAccentable()
            Text(verbatim: "L \(pct(.left))   R \(pct(.right))")
                .font(.system(.body, design: .rounded).monospacedDigit())
            Text(verbatim: "Case \(pct(.enclosure))").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pct(_ bud: Bud) -> String { s.battery[bud]?.percent.map { "\($0)%" } ?? "—" }
}

struct InlineView: View {
    let s: BudsSnapshot

    var body: some View {
        Label(s.budsPercent.map { "Buds \($0)%" } ?? "Buds", systemImage: "earbuds")
    }
}
