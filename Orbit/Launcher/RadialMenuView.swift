import SwiftUI
import AppKit
import Combine
import IOKit.ps

// MARK: - Container

struct RadialContainerView: View {
    let rootItems:       [OrbitItem]
    let center:          CGPoint
    let keyPublisher:    AnyPublisher<NSEvent, Never>
    let scrollPublisher: AnyPublisher<CGFloat, Never>
    let onDismiss:       () -> Void

    @State private var navStack: [NavLevel] = []

    private struct NavLevel {
        let title: String
        let items: [OrbitItem]
    }

    private var currentItems: [OrbitItem] { navStack.last?.items ?? rootItems }
    private var depth: Int { navStack.count }

    var body: some View {
        RadialMenuView(
            items:           currentItems,
            center:          center,
            isNested:        depth > 0,
            keyPublisher:    keyPublisher,
            scrollPublisher: scrollPublisher,
            onSelect: { item in
                if case .submenu(let children) = item.kind {
                    navStack.append(NavLevel(title: item.title, items: children))
                } else {
                    UsageTracker.shared.recordOpen(item: item)
                    item.perform()
                    onDismiss()
                }
            },
            onBack:    depth > 0 ? { navStack.removeLast() } : nil,
            onDismiss: onDismiss
        )
        .id(depth)
        .onReceive(keyPublisher) { event in
            if event.keyCode == 53 {          // Esc
                if !navStack.isEmpty { navStack.removeLast() }
                else { onDismiss() }
            }
        }
    }
}

// MARK: - Radial View

struct RadialMenuView: View {
    let items:           [OrbitItem]
    let center:          CGPoint
    var isNested:        Bool = false
    let keyPublisher:    AnyPublisher<NSEvent, Never>
    let scrollPublisher: AnyPublisher<CGFloat, Never>
    let onSelect:        (OrbitItem) -> Void
    var onBack:          (() -> Void)? = nil
    let onDismiss:       () -> Void

    private let radius:  CGFloat = 130
    private let iconSize: CGFloat = 52
    private let perPage = OrbitItem.itemsPerPage

    @State private var appeared  = false
    @State private var hoveredID: UUID?
    @State private var page      = 0

    private var totalPages: Int { max(1, (items.count + perPage - 1) / perPage) }

    private var pageItems: [OrbitItem] {
        let start = page * perPage
        let end   = min(start + perPage, items.count)
        guard start < end else { return [] }
        return Array(items[start..<end])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Tap-to-dismiss background (plain SwiftUI — no NSView blocking clicks)
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Group {
                if items.isEmpty { emptyState }
                else             { radialContent }
            }
            .scaleEffect(appeared ? 1.0 : 0.82)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: appeared)
            .position(center)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { appeared = true }
        }
        .onReceive(keyPublisher)    { handleKey($0) }
        .onReceive(scrollPublisher) { flipPage(by: $0 > 0 ? -1 : 1) }
    }

    // MARK: - Radial Content

    private var radialContent: some View {
        // Precompute intensities once per render
        let max = pageItems.map { usageScore($0) }.max() ?? 0

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(0.75))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 310, height: 310)
                .shadow(color: .black.opacity(0.4), radius: 40, y: 12)

            ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                let angle     = angleFor(index: index, total: pageItems.count)
                let r         = appeared ? radius : 0
                let delay     = Double(index) * 0.025
                let intensity = max > 0 ? usageScore(item) / max : 0

                OrbitItemButton(
                    item:      item,
                    size:      iconSize,
                    isHovered: hoveredID == item.id,
                    intensity: intensity > 0 ? intensity : nil,
                    badge:     keyBadge(for: index)
                ) { onSelect(item) }
                .onHover { inside in hoveredID = inside ? item.id : nil }
                .offset(x: cos(angle) * r, y: sin(angle) * r)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.68).delay(delay), value: appeared)
            }

            VStack(spacing: 6) {
                centerContent
                if totalPages > 1 { pageDots }
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        if let back = onBack {
            Button(action: back) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }.buttonStyle(.plain)
        } else {
            LiveWidgetView()
        }
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalPages, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == page ? 6 : 4, height: i == page ? 6 : 4)
                    .animation(.spring(response: 0.2), value: page)
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 8)
            VStack(spacing: 10) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                Text(L("No items")).font(.headline)
                Text(L("Open Settings to add items")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) {
        guard event.keyCode != 53 else { return }
        switch event.keyCode {
        case 123: flipPage(by: -1)   // ←
        case 124: flipPage(by:  1)   // →
        default:
            if let char = event.charactersIgnoringModifiers,
               let num = Int(char), num >= 1, num <= 9 {
                let idx = num - 1
                if idx < pageItems.count { onSelect(pageItems[idx]) }
            }
        }
    }

    private func flipPage(by delta: Int) {
        let next = page + delta
        guard next >= 0, next < totalPages else { return }
        withAnimation(.spring(response: 0.25)) { page = next }
    }

    // MARK: - Helpers

    private func angleFor(index: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return (2 * .pi / CGFloat(total)) * CGFloat(index) - .pi / 2
    }

    private func keyBadge(for index: Int) -> String? {
        index < 9 ? "\(index + 1)" : nil
    }

    private func usageScore(_ item: OrbitItem) -> Double {
        UsageTracker.shared.intensity(for: item, among: pageItems).map { $0 } ?? 0
    }
}

// MARK: - Live Widget

private struct LiveWidgetView: View {
    @State private var timeString = ""
    @State private var battery: BatteryState? = nil
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 3) {
            Text(timeString)
                .font(.system(size: 17, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
            if let bat = battery {
                HStack(spacing: 3) {
                    Image(systemName: bat.isCharging ? "bolt.fill" : bat.iconName)
                        .font(.system(size: 9))
                    Text("\(bat.level)%")
                        .font(.system(size: 10, weight: .light))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        timeString = fmt.string(from: Date())
        battery = BatteryState.current()
    }
}

private struct BatteryState {
    let level: Int
    let isCharging: Bool

    var iconName: String {
        switch level {
        case 0..<20:  return "battery.0"
        case 20..<40: return "battery.25"
        case 40..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default:      return "battery.100"
        }
    }

    static func current() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max     = desc[kIOPSMaxCapacityKey]     as? Int,
                  max > 0 else { continue }
            return BatteryState(level: current * 100 / max,
                                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}

// MARK: - Item Button

struct OrbitItemButton: View {
    let item:      OrbitItem
    let size:      CGFloat
    let isHovered: Bool
    var intensity: Double? = nil   // 0…1; nil = no dot
    var badge:     String? = nil
    let action:    () -> Void

    private var dotColor: Color? {
        guard let v = intensity else { return nil }
        switch v {
        case 0..<0.33: return .green
        case 0.33..<0.66: return .yellow
        default: return .red
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: item.icon)
                        .resizable().interpolation(.high)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(isHovered ? 0.4 : 0), lineWidth: 1.5)
                        )
                        .overlay(alignment: .topLeading) {
                            if let color = dotColor {
                                Circle()
                                    .fill(color)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: color, radius: 3)
                                    .offset(x: -2, y: -2)
                            }
                        }

                    if item.isSubmenu {
                        Image(systemName: "chevron.forward.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: 4)
                    } else if let b = badge, !isHovered {
                        Text(b)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                }

                Text(item.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .lineLimit(1)
                    .frame(maxWidth: size + 12)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.18 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
    }
}
