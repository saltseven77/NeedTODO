import WidgetKit
import SwiftUI

struct CalendarEntry: TimelineEntry {
    let date: Date
    let name: String
    let tasks: [[String: Any]]
    let background: Color
    let text: Color
    let accent: Color
}
private func color(_ value: Any?, fallback: UInt32) -> Color {
    let argb = (value as? NSNumber)?.uint32Value ?? fallback
    return Color(.sRGB, red: Double((argb >> 16) & 255) / 255, green: Double((argb >> 8) & 255) / 255, blue: Double(argb & 255) / 255, opacity: Double((argb >> 24) & 255) / 255)
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry { load(Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) { completion(load(Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        completion(Timeline(entries: [load(now), load(midnight)], policy: .after(now.addingTimeInterval(1800))))
    }
    func load(_ date: Date) -> CalendarEntry {
        var snapshot: [String: Any] = [:]
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.needtodo.shared"),
           let bytes = try? Data(contentsOf: container.appendingPathComponent("snapshot.json")),
           let decoded = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] { snapshot = decoded }
        let theme = snapshot["calendar"] as? [String: Any] ?? [:]
        let palettes = theme["palettes"] as? [[String: Any]] ?? []
        let palette = palettes.first { ($0["id"] as? String) == (theme["paletteId"] as? String) } ?? [:]
        return CalendarEntry(date: date, name: theme["name"] as? String ?? "泥土豆", tasks: snapshot["tasks"] as? [[String: Any]] ?? [], background: color(palette["background"], fallback: 0xfff7f8fa), text: color(palette["text"], fallback: 0xff34475e), accent: color(palette["accent"], fallback: 0xff527ca7))
    }
}
struct CalendarView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalendarEntry
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private func key(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private var days: [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date))!
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: first) }
    }
    private func tasks(_ date: Date) -> [[String: Any]] { entry.tasks.filter { ($0["date"] as? String) == key(date) && ($0["scope"] as? String) == "day" && ($0["done"] as? Bool) != true && ($0["deleted"] as? Bool) != true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text("\(calendar.component(.month, from: entry.date))月").font(.system(size: 12)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: family == .systemLarge ? 10 : 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.system(size: 9)).opacity(0.5) }
                ForEach(days, id: \.self) { date in
                    Link(destination: URL(string: "needtodo://calendar?date=\(key(date))")!) {
                        VStack(spacing: 1) {
                            Text("\(calendar.component(.day, from: date))").font(.system(size: 11, weight: calendar.isDate(date, inSameDayAs: entry.date) ? .bold : .regular))
                            Circle().fill(tasks(date).isEmpty ? .clear : entry.accent).frame(width: 3, height: 3)
                        }.frame(maxWidth: .infinity).foregroundStyle(calendar.isDate(date, inSameDayAs: entry.date) ? entry.accent : entry.text).opacity(calendar.component(.month, from: date) == calendar.component(.month, from: entry.date) ? 1 : 0.3)
                    }
                }
            }
            if family == .systemLarge {
                ForEach(Array(tasks(entry.date).prefix(3).enumerated()), id: \.offset) { _, task in Text(task["title"] as? String ?? "").font(.system(size: 12)).lineLimit(1) }
            }
        }.foregroundStyle(entry.text).containerBackground(entry.background, for: .widget)
    }
}
@main
struct NeedTODOWidget: Widget {
    let kind = "NeedTODOCalendar"
    var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: Provider()) { CalendarView(entry: $0) }.configurationDisplayName("泥土豆月历").description("月历与日程").supportedFamilies([.systemSmall, .systemMedium, .systemLarge]) }
}
