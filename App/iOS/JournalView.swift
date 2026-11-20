import SwiftUI

struct JournalView: View {
    @EnvironmentObject var model: AppModel
    @State private var month = Date()
    @State private var selectedDay = Date()
    @State private var yearMode = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = model.preferences.mondayFirst ? 2 : 1; return c }
    private func key(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private func displayFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
    private var shownRecords: [SessionRecord] {
        if !search.isEmpty { return model.visibleRecords.filter { ($0.note + " " + $0.dayKey + " " + $0.links.map { $0.title + " " + $0.url }.joined(separator: " ")).localizedCaseInsensitiveContains(search) } }
        let selectedKey = key(selectedDay)
        return model.visibleRecords.filter { $0.dayKey == selectedKey }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                if !searchFocused && search.isEmpty {
                HStack {
                    Button("月") { yearMode = false }.foregroundStyle(yearMode ? EnchantTheme.muted : EnchantTheme.accent)
                    Button("年") { yearMode = true }.foregroundStyle(yearMode ? EnchantTheme.accent : EnchantTheme.muted)
                    Spacer(); Button { move(-1) } label: { Text("‹") }.accessibilityLabel(L10n.text(yearMode ? "上一年" : "上个月"))
                    Text(yearMode ? L10n.format("%ld年", calendar.component(.year, from: month)) : displayFormatter(template: "yMMM").string(from: month)).font(EnchantTheme.body(16))
                    Button { move(1) } label: { Text("›") }.accessibilityLabel(L10n.text(yearMode ? "下一年" : "下个月"))
                    Button("今天") { month = Date(); selectedDay = Date(); yearMode = false }.font(EnchantTheme.body(12))
                }.buttonStyle(.plain).frame(height: 44)
                VStack(spacing: 8) {
                    if yearMode { yearGrid(rowHeight: min(70, max(48, (geometry.size.height - 290) / 4))) }
                    else { monthGrid(rowHeight: min(44, max(30, (geometry.size.height - 306) / 6))) }
                }.padding(10).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { if abs($0.translation.width) > abs($0.translation.height) { move($0.translation.width > 0 ? -1 : 1) } })
                }
                HStack {
                    PixelIcon(name: "journal", size: 16)
                    TextField("搜索日期或备注", text: $search).font(EnchantTheme.body(14)).accessibilityLabel("搜索记录").focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    if searchFocused || !search.isEmpty { Button("取消") { search = ""; searchFocused = false }.buttonStyle(.plain).font(EnchantTheme.body(14)) }
                }.padding(.horizontal, 12).frame(height: 44).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                HStack { Text(search.isEmpty ? key(selectedDay) : L10n.text("搜索结果")).font(EnchantTheme.body(14)); Spacer(); Text(L10n.format("%ld 条", shownRecords.count)).foregroundStyle(EnchantTheme.muted) }.frame(height: 32)
                if shownRecords.isEmpty {
                    VStack(spacing: 6) { Illustration(name: "Journal", size: min(54, geometry.size.height * 0.08)); Text(L10n.text(search.isEmpty ? "这页还空着" : "没有匹配记录")).font(EnchantTheme.body(16)) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView { LazyVStack(spacing: 8) { ForEach(shownRecords) { record in NavigationLink { RecordDetail(recordID: record.id) } label: { RecordRow(record: record).padding(12).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain).accessibilityIdentifier("record-row") } } }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).frame(maxHeight: .infinity)
                }
            }.padding(.horizontal, 16).padding(.bottom, 10).frame(width: geometry.size.width, height: geometry.size.height)
        }.background(EnchantTheme.background).navigationTitle("魔法手账").navigationBarTitleDisplayMode(.inline)
    }
    private func monthGrid(rowHeight: CGFloat) -> some View {
        let gridCalendar = calendar
        let start = gridCalendar.date(from: gridCalendar.dateComponents([.year, .month], from: month))!
        let days = gridCalendar.range(of: .day, in: .month, for: start)!.count
        let offset = (gridCalendar.component(.weekday, from: start) - gridCalendar.firstWeekday + 7) % 7
        let monthKey = String(key(start).prefix(7))
        let dayCounts = model.visibleRecords.reduce(into: [String: Int]()) { $0[$1.dayKey, default: 0] += 1 }
        let labels = model.preferences.mondayFirst ? ["一", "二", "三", "四", "五", "六", "日"] : ["日", "一", "二", "三", "四", "五", "六"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in Text(L10n.text(label)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).frame(height: 24) }
            ForEach(0..<((offset + days + 6) / 7 * 7), id: \.self) { index in
                let day = index - offset + 1
                if day > 0 && day <= days {
                    let date = gridCalendar.date(byAdding: .day, value: day - 1, to: start)!
                    let dateKey = monthKey + String(format: "-%02ld", day)
                    let count = dayCounts[dateKey, default: 0]
                    let selected = gridCalendar.isDate(date, inSameDayAs: selectedDay)
                    Button { selectedDay = date } label: {
                        VStack(spacing: 1) { Text(String(day)).font(EnchantTheme.digits(16)); Text(count == 0 ? " " : L10n.format("%ld 次", count)).font(EnchantTheme.body(10)) }
                            .frame(maxWidth: .infinity, minHeight: rowHeight).foregroundStyle(count > 0 ? EnchantTheme.magic : EnchantTheme.ink)
                            .background(selected ? EnchantTheme.magic.opacity(0.18) : count > 0 ? EnchantTheme.magic.opacity(count >= 3 ? 0.14 : 0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(gridCalendar.isDateInToday(date) ? EnchantTheme.accent : selected ? EnchantTheme.magic : .clear))
                    }.buttonStyle(.plain).accessibilityLabel(L10n.format("%@，%ld 条记录", dateKey, count))
                } else { Color.clear.frame(height: rowHeight).accessibilityHidden(true) }
            }
        }
    }
    private func yearGrid(rowHeight: CGFloat) -> some View {
        let gridCalendar = calendar
        let year = gridCalendar.component(.year, from: month)
        let formatter = displayFormatter(template: "MMM")
        let monthCounts = model.visibleRecords.reduce(into: [String: Int]()) { $0[String($1.dayKey.prefix(7)), default: 0] += 1 }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(1...12, id: \.self) { number in
                let prefix = String(format: "%04ld-%02ld", year, number)
                let count = monthCounts[prefix, default: 0]
                let date = gridCalendar.date(from: DateComponents(year: year, month: number, day: 1))!
                let label = formatter.string(from: date)
                Button { month = date; selectedDay = month; yearMode = false } label: {
                    VStack(spacing: 8) { Text(label).font(EnchantTheme.body(16)); Text(L10n.format("%ld 次", count)).font(EnchantTheme.body(12)).foregroundStyle(count > 0 ? EnchantTheme.magic : EnchantTheme.muted) }.frame(maxWidth: .infinity, minHeight: rowHeight).background(EnchantTheme.magic.opacity(count > 15 ? 0.24 : count > 5 ? 0.15 : count > 0 ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel(label)
            }
        }
    }
    private func move(_ direction: Int) { month = calendar.date(byAdding: yearMode ? .year : .month, value: direction, to: month)!; if !yearMode { selectedDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))! } }
}
struct RecordRow: View {
    let record: SessionRecord
    var body: some View {
        HStack(spacing: 16) {
            Illustration(name: "Journal", size: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.startTimeInSavedZone).font(EnchantTheme.body(16)).foregroundStyle(EnchantTheme.ink)
                Text(record.note.isEmpty ? L10n.format("%@记录 · %@", record.originLabel, record.dayKey) : record.note).lineLimit(1).font(EnchantTheme.body(16)).foregroundStyle(EnchantTheme.muted)
            }
            Spacer(minLength: 4); Text(record.formattedDuration).font(EnchantTheme.digits(16)).foregroundStyle(EnchantTheme.accent); Image(systemName: "chevron.right").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted)
        }.frame(minHeight: 44)
    }
}
