// The Mac app's design language on iOS: Droppy's tile hues, glass cards, segmented tiles, battery rings.

import SwiftUI

enum Theme {
    static let tileHues: [Color] = [
        Color(red: 0.345, green: 0.337, blue: 0.839),
        Color(red: 1.000, green: 0.584, blue: 0.000),
        Color(red: 0.188, green: 0.690, blue: 0.780),
        Color(red: 0.686, green: 0.322, blue: 0.871),
        Color(red: 0.204, green: 0.780, blue: 0.349),
        Color(red: 0.040, green: 0.478, blue: 1.000),
        Color(red: 0.925, green: 0.282, blue: 0.600),
        Color(red: 0.800, green: 0.565, blue: 0.145),
        Color(red: 0.353, green: 0.400, blue: 0.459),
    ]
    static let cardRadius: CGFloat = 24
    static func overlay(_ opacity: Double) -> Color { Color.primary.opacity(opacity) }
    static var spring: Animation { .spring(response: 0.32, dampingFraction: 0.9) }
}

/// The purple-to-orange field the README screenshots use, so the glass has colour to bend.
struct Backdrop: View {
    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.55, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            Color(red: 0.34, green: 0.27, blue: 0.86), Color(red: 0.62, green: 0.36, blue: 0.55), Color(red: 1.0, green: 0.47, blue: 0.24),
            Color(red: 0.20, green: 0.45, blue: 0.85), Color(red: 0.86, green: 0.50, blue: 0.45), Color(red: 0.93, green: 0.36, blue: 0.40),
            Color(red: 0.12, green: 0.55, blue: 0.80), Color(red: 0.80, green: 0.25, blue: 0.55), Color(red: 0.50, green: 0.22, blue: 0.78),
        ])
        .overlay(Color.black.opacity(0.28))
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct CardSection<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal, 6)
            content
        }
    }
}

struct IconTile: View {
    let symbol: String
    let hue: Int
    var size: CGFloat = 30

    var body: some View {
        let color = Theme.tileHues[hue % Theme.tileHues.count]
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}

struct Row<Leading: View, Control: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder var leading: Leading
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body)
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct RowDivider: View {
    var inset: CGFloat = 56
    var body: some View { Divider().padding(.leading, inset) }
}

/// Equal cells with a highlight that slides between them.
struct TileSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String, symbol: String)]
    let selection: Value?
    var tall = false
    let onSelect: (Value) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection
                Button { onSelect(option.value) } label: {
                    VStack(spacing: tall ? 6 : 4) {
                        Image(systemName: option.symbol).font(.system(size: tall ? 17 : 13, weight: .medium))
                        Text(verbatim: option.title).font(.system(size: tall ? 12 : 11, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: tall ? 62 : 48)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.overlay(0.14))
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isSelected)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(Theme.spring, value: selection)
    }
}

struct BatteryRing: View {
    let bud: Bud
    let level: BatteryReading?
    let placement: Placement?
    var size: CGFloat = 58

    var body: some View {
        let fraction = Double(level?.percent ?? 0) / 100
        let color: Color = level?.charging == true ? .green
            : (level?.percent ?? 100) <= 20 ? .red : Color.primary.opacity(0.85)
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.overlay(0.12), lineWidth: 4.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.5), value: fraction)
                Image(systemName: bud.symbol)
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(Color.primary.opacity(level?.percent == nil ? 0.35 : 0.9))
                if level?.charging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.green).offset(y: size * 0.3)
                }
            }
            .frame(width: size, height: size)
            VStack(spacing: 1) {
                Text(verbatim: level?.percent.map { "\($0)%" } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        if bud == .enclosure { return level?.percent == nil ? "Closed" : "Case" }
        return "\(bud.label) · \(placement?.label ?? "—")"
    }
}

struct EventRow: View {
    let event: TouchEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(event.isTouch ? .orange : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title).font(.subheadline.weight(.medium))
                Text(verbatim: event.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
