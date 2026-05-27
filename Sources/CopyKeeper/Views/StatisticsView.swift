import SwiftUI
import Charts
import AppKit

struct StatisticsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject private var appSettings = AppSettings.shared
    let onClose: () -> Void

    @State private var hoveredType: String?

    var body: some View {
        ZStack {
            glassBackground

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        cacheBlock
                        metricsRow

                        section(Loc.s("Очистка групп", "Clear Groups")) { groupsList }
                        section(Loc.s("Активность за 14 дней", "Activity (14 days)")) { perDayChart }
                        section(Loc.s("По типам", "By Type")) { typeChart }
                        section(Loc.s("Топ приложений", "Top Apps")) { topAppsList }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
        .frame(width: 580, height: 680)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Background

    private var glassBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.40)
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.15).opacity(0.22),
                         Color(red: 0.95, green: 0.3, blue: 0.45).opacity(0.08),
                         .clear],
                startPoint: .bottom, endPoint: .top
            )
            RadialGradient(
                colors: [Color(red: 0.7, green: 0.35, blue: 0.95).opacity(0.16), .clear],
                center: .init(x: 0.9, y: 0.0),
                startRadius: 0, endRadius: 460
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Loc.s("Статистика", "Statistics"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain).hoverHighlight()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Cache block

    private var cacheBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
                Text(Loc.s("Размер кэша", "Cache Size"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(store.items.count) \(Loc.s("записей", "items"))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Text(cacheString)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            pillButton(Loc.s("Очистить весь буфер", "Clear Entire Buffer"),
                       color: Color(red: 1.0, green: 0.35, blue: 0.4)) {
                if Confirm.destructive(Loc.s("Очистить весь буфер?", "Clear entire clipboard?"),
                                       info: Loc.s("Все скопированные элементы будут удалены.",
                                                   "All copied items will be deleted."),
                                       confirmTitle: Loc.s("Очистить", "Clear")) {
                    store.clearAll()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
    }

    private func pillButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(color.opacity(0.85)))
        }
        .buttonStyle(.plain).hoverHighlight()
    }

    // MARK: - Metrics

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(Loc.s("Скопировано всего", "Copied Total"), "\(store.totalCopied)", "doc.on.doc", .blue)
            metricCard(Loc.s("Сейчас хранится", "Stored Now"), "\(store.items.count)", "tray.full", .green)
            metricCard(Loc.s("Работает", "Active"), activeString, "clock", .purple)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104)
        .padding(14)
        .background(cardFill)
    }

    private var cardFill: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Charts

    private var perDayChart: some View {
        Chart(perDayData) { point in
            BarMark(
                x: .value("День", point.day, unit: .day),
                y: .value("Копий", point.count)
            )
            .foregroundStyle(Color.blue.gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                AxisValueLabel().foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 170)
        .padding(14)
        .background(cardFill)
    }

    private var typeChart: some View {
        Chart(typeData) { point in
            BarMark(
                x: .value("Тип", point.label),
                y: .value("Кол-во", point.count)
            )
            .foregroundStyle(point.color)
            .cornerRadius(6)
            .annotation(position: .top, spacing: 4) {
                Text("\(point.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                AxisValueLabel().foregroundStyle(.white.opacity(0.5))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let origin = geo[proxy.plotAreaFrame].origin
                                if let label: String = proxy.value(atX: location.x - origin.x) {
                                    hoveredType = label
                                }
                            case .ended:
                                hoveredType = nil
                            }
                        }

                    if let type = hoveredType,
                       let point = typeData.first(where: { $0.label == type }) {
                        let origin = geo[proxy.plotAreaFrame].origin
                        let barX = (proxy.position(forX: point.label) ?? 0) + origin.x
                        let barTopY = (proxy.position(forY: point.count) ?? 0) + origin.y
                        Text(point.sizeString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.85)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .fixedSize()
                            .position(x: barX, y: max(12, barTopY - 16))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 170)
        .padding(14)
        .background(cardFill)
    }

    private var groupsList: some View {
        let subgroups = Array(store.groups.enumerated()).filter { !$0.element.isDefault }
        return VStack(spacing: 10) {
            if subgroups.isEmpty {
                Text(Loc.s("Нет пользовательских групп", "No custom groups"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(subgroups, id: \.element.id) { index, group in
                    HStack(spacing: 10) {
                        if let emoji = group.emoji, !emoji.isEmpty {
                            Text(emoji)
                                .font(.system(size: 14))
                        } else {
                            Circle()
                                .fill(GroupBarView.color(for: group, fallbackIndex: index))
                                .frame(width: 9, height: 9)
                        }
                        Text(group.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Loc.items(group.itemIDs.count)) · \(groupSize(group))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                        Button {
                            if Confirm.destructive(Loc.s("Очистить группу «\(group.name)»?", "Clear group “\(group.name)”?"),
                                                   info: Loc.s("Записи группы будут удалены.", "Items in this group will be deleted."),
                                                   confirmTitle: Loc.s("Очистить", "Clear")) {
                                store.clearGroup(group)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text(Loc.s("Очистить", "Clear"))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(red: 1.0, green: 0.35, blue: 0.4).opacity(0.85)))
                        }
                        .buttonStyle(.plain).hoverHighlight()
                    }
                }
            }
        }
        .padding(14)
        .background(cardFill)
    }

    private var topAppsList: some View {
        VStack(spacing: 10) {
            if topApps.isEmpty {
                Text(Loc.s("Пока нет данных", "No data yet"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(topApps) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 22, height: 22)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(app.name)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    GeometryReader { geo in
                        let fraction = maxAppCount > 0 ? CGFloat(app.count) / CGFloat(maxAppCount) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Color.blue.opacity(0.7))
                                .frame(width: max(6, geo.size.width * fraction))
                        }
                    }
                    .frame(width: 150, height: 8)
                    Text("\(app.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(cardFill)
    }

    // MARK: - Section wrapper

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            content()
        }
    }

    // MARK: - Derived data

    private var cacheString: String {
        ByteCountFormatter.string(fromByteCount: store.cacheSizeBytes(), countStyle: .file)
    }

    private var activeString: String {
        let seconds = Int(Date().timeIntervalSince(store.firstLaunchDate))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return Loc.s("\(days)д \(hours)ч \(minutes)м", "\(days)d \(hours)h \(minutes)m") }
        if hours > 0 { return Loc.s("\(hours)ч \(minutes)м", "\(hours)h \(minutes)m") }
        return Loc.s("\(minutes)м", "\(minutes)m")
    }

    private func groupSize(_ group: ClipboardGroup) -> String {
        ByteCountFormatter.string(fromByteCount: store.groupSizeBytes(group), countStyle: .file)
    }

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let count: Int
    }

    private var perDayData: [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let count = store.items.filter { cal.isDate($0.timestamp, inSameDayAs: day) }.count
            return DayPoint(day: day, count: count)
        }
    }

    private struct TypePoint: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
        let bytes: Int64

        var sizeString: String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    private var typeData: [TypePoint] {
        ContentType.allCases.compactMap { type in
            let items = store.items.filter { $0.type == type }
            guard !items.isEmpty else { return nil }
            let bytes = items.reduce(Int64(0)) { $0 + store.sizeBytes(for: $1) }
            return TypePoint(label: typeLabel(type), count: items.count,
                             color: typeColor(type), bytes: bytes)
        }
    }

    private struct AppPoint: Identifiable {
        var id: String { name }
        let name: String
        let count: Int
        let icon: NSImage?
    }

    private var topApps: [AppPoint] {
        let grouped = Dictionary(grouping: store.items) { $0.sourceApp?.name ?? Loc.s("Неизвестно", "Unknown") }
        return grouped.map { name, items -> AppPoint in
            let src = items.first?.sourceApp
            let icon = IconStore.shared.nsImage(for: src?.bundleID)
                ?? src?.iconData.flatMap { NSImage(data: $0) }
            return AppPoint(name: name, count: items.count, icon: icon)
        }
        // Stable order: by count desc, then name — so the list never reshuffles on re-render.
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        .prefix(5)
        .map { $0 }
    }

    private var maxAppCount: Int {
        topApps.map(\.count).max() ?? 0
    }

    private func typeLabel(_ type: ContentType) -> String {
        switch type {
        case .text:  return Loc.s("Текст", "Text")
        case .url:   return Loc.s("Ссылки", "Links")
        case .code:  return Loc.s("Код", "Code")
        case .image: return Loc.s("Картинки", "Images")
        case .color: return Loc.s("Цвета", "Colors")
        }
    }

    private func typeColor(_ type: ContentType) -> Color {
        switch type {
        case .text:  return Color(red: 0.98, green: 0.62, blue: 0.20)
        case .url:   return Color(red: 0.27, green: 0.55, blue: 1.0)
        case .code:  return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .image: return Color(red: 1.0, green: 0.38, blue: 0.42)
        case .color: return Color(red: 1.0, green: 0.42, blue: 0.68)
        }
    }
}
