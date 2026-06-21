import SwiftUI

/// BuhoCleaner-style detail popover: a fixed 2-column card grid plus cores and
/// top-CPU sections. Binds only to `MonitorViewModel` (MVVM). Fixed width and
/// fixed-height sections mean the popover never jumps or clips.
struct MonitorPopoverView: View {
    @ObservedObject var vm: MonitorViewModel
    @ObservedObject private var controls = SystemControls.shared
    let onOpenSettings: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // System sliders
            VStack(spacing: 6) {
                ControlSliderRow(
                    icon: "speaker.wave.2",
                    value: Binding(
                        get: { Double(controls.volume) },
                        set: { controls.setVolume(Float($0)) }
                    )
                )
                if controls.brightnessAvailable {
                    ControlSliderRow(
                        icon: "sun.max",
                        value: Binding(
                            get: { Double(controls.brightness) },
                            set: { controls.setBrightness(Float($0)) }
                        )
                    )
                }
            }
            .onAppear { controls.refreshFromSystem() }

            Divider()

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(vm.cards) { card in
                    CardView(card: card)
                }
            }

            if vm.cards.contains(where: { $0.metric == .cpu }) {
                section(L("Cores")) {
                    CoreBars(cores: vm.cores).frame(height: 26)
                }
            }

            section(L("Top CPU")) {
                VStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        HStack {
                            Text(i < vm.topProcesses.count ? vm.topProcesses[i].name : " ")
                                .lineLimit(1)
                            Spacer()
                            if i < vm.topProcesses.count {
                                Text(String(format: "%.0f%%", vm.topProcesses[i].cpu))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .frame(height: 15)
                    }
                }
            }

            Divider()
            Button(action: onOpenSettings) {
                Label(L("Settings…"), systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Control Slider Row

private struct ControlSliderRow: View {
    let icon: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(value: $value, in: 0...1)
                .controlSize(.small)
        }
    }
}

// MARK: - Card

private struct CardView: View {
    let card: MetricCardVM

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: card.icon).font(.caption).foregroundStyle(card.supported ? card.tint : .secondary)
                Text(card.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            if !card.supported {
                Text(card.note).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            } else {
                Text(card.bigValue)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(card.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let history = card.history {
                    Sparkline(values: history, color: card.tint).frame(height: 14)
                } else if let bar = card.barFraction {
                    HStack(spacing: 6) {
                        MiniBar(value: bar, tint: card.tint).frame(height: 5)
                        if let s = card.secondary {
                            Text(s).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else if let s = card.secondary {
                    Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }
}

// MARK: - Canvas primitives (no layout feedback)

private struct Sparkline: View {
    let values: [Double]
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxV = max(values.max() ?? 1, 0.0001)
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - CGFloat(v / maxV))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

private struct CoreBars: View {
    let cores: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard !cores.isEmpty else { return }
            let gap: CGFloat = 3
            let w = max(1, (size.width - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count))
            for (i, usage) in cores.enumerated() {
                let x = CGFloat(i) * (w + gap)
                let track = CGRect(x: x, y: 0, width: w, height: size.height)
                ctx.fill(Path(roundedRect: track, cornerRadius: 1.5), with: .color(.secondary.opacity(0.15)))
                let h = max(2, size.height * CGFloat(min(1, usage)))
                let bar = CGRect(x: x, y: size.height - h, width: w, height: h)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(.green))
            }
        }
    }
}

private struct MiniBar: View {
    let value: Double
    var tint: Color
    var body: some View {
        Canvas { ctx, size in
            let r = size.height / 2
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r),
                     with: .color(.secondary.opacity(0.15)))
            let w = max(0, min(1, value)) * size.width
            if w > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: size.height), cornerRadius: r),
                         with: .color(tint))
            }
        }
    }
}
