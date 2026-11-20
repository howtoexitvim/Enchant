import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
enum EnchantTheme {
    static let background = Color(hex: 0x110D1B), surface = Color(hex: 0x211A30), raised = Color(hex: 0x30243F)
    static let border = Color(hex: 0x594568), ink = Color(hex: 0xF4EFDD), muted = Color(hex: 0xB7A8C6)
    static let accent = Color(hex: 0x57E0CD), magic = Color(hex: 0xAE78F6), gold = Color(hex: 0xF2CA6B), danger = Color(hex: 0xEF8499)
    static func title(_ size: CGFloat = 24) -> Font { .custom("Fusion-Pixel-12px-Prop-zh-Hans-Regular", size: size, relativeTo: .title2) }
    static func body(_ size: CGFloat = 16) -> Font { .custom("Fusion-Pixel-12px-Prop-zh-Hans-Regular", size: size, relativeTo: .body) }
    static func digits(_ size: CGFloat = 28) -> Font { .custom("Silkscreen-Regular", size: size, relativeTo: .title) }
}
#if os(watchOS)
private struct WatchControlScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
extension EnvironmentValues {
    var watchControlScale: CGFloat {
        get { self[WatchControlScaleKey.self] }
        set { self[WatchControlScaleKey.self] = newValue }
    }
}
#endif
struct EnchantButton: ButtonStyle {
    var secondary = false
    var fontSize: CGFloat = 18
    #if os(watchOS)
    @Environment(\.watchControlScale) private var watchScale
    #endif
    func makeBody(configuration: Configuration) -> some View {
        #if os(watchOS)
        // Scale the visible face with the display, while keeping a 44pt touch region.
        configuration.label.font(EnchantTheme.body(max(14, fontSize * watchScale))).lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 6 * watchScale)
            .frame(maxWidth: .infinity).frame(height: 44 * watchScale)
            .foregroundStyle(secondary ? EnchantTheme.ink : EnchantTheme.background)
            .background(secondary ? EnchantTheme.raised : EnchantTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12 * watchScale))
            .frame(minHeight: 44).contentShape(RoundedRectangle(cornerRadius: 12 * watchScale)).opacity(configuration.isPressed ? 0.7 : 1)
        #else
        configuration.label.font(EnchantTheme.body(fontSize)).lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(minHeight: 48)
            .foregroundStyle(secondary ? EnchantTheme.ink : EnchantTheme.background)
            .background(secondary ? EnchantTheme.raised : EnchantTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(RoundedRectangle(cornerRadius: 12)).opacity(configuration.isPressed ? 0.7 : 1)
        #endif
    }
}
struct EnchantCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(EnchantTheme.border.opacity(0.5))) }
}
struct Illustration: View {
    let name: String; var size: CGFloat = 120
    var body: some View { Image(name).resizable().interpolation(.none).scaledToFit().frame(width: size, height: size).accessibilityHidden(true) }
}
struct MetricView: View {
    let title: String; let value: String; var color = EnchantTheme.accent
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(value).font(EnchantTheme.digits(22)).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1); Text(LocalizedStringKey(title)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct EmptyState: View {
    let title: String; let message: String; var icon: String? = nil
    var body: some View { VStack(spacing: 12) { Group { if let icon { PixelIcon(name: icon, size: 100) } else { Illustration(name: "Journal", size: 100) } }; Text(LocalizedStringKey(title)).font(EnchantTheme.title()); Text(LocalizedStringKey(message)).font(EnchantTheme.body(16)).foregroundStyle(EnchantTheme.muted).multilineTextAlignment(.center) }.padding(24).frame(maxWidth: .infinity) }
}
extension SessionRecord {
    var originLabel: String { switch origin { case .manual: return L10n.text("手动"); case .automatic: return L10n.text("自动"); case .backfill: return L10n.text("补记") } }
    var formattedDuration: String { Self.durationString(activeDuration(at: endedAt ?? lastCheckpoint)) }
    static func durationString(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "--" }
        let n = Int(value)
        return n >= 3600 ? String(format: "%ld:%02ld:%02ld", n / 3600, n / 60 % 60, n % 60) : String(format: "%02ld:%02ld", n / 60, n % 60)
    }
    var startTimeInSavedZone: String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: timeZoneID); formatter.dateFormat = "HH:mm"; return formatter.string(from: startedAt)
    }
}

extension RecordLink {
    static func detected(in text: String) -> [RecordLink] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url?.absoluteString, seen.insert(url).inserted else { return nil }
            return try? RecordLink(title: "", url: url)
        }.prefix(20).map { $0 }
    }
}
extension SessionRecord {
    var journalText: String { note + links.filter { !note.contains($0.url) }.map { "\n\n" + ($0.title.isEmpty ? "" : $0.title + "\n") + $0.url }.joined() }
}
struct JournalNoteText: View {
    let text: String
    private var attributed: AttributedString {
        let value = NSMutableAttributedString(string: text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = match.url, (try? RecordLink(title: "", url: url.absoluteString)) != nil { value.addAttribute(.link, value: url, range: match.range) }
            }
        }
        return (try? AttributedString(value, including: \.foundation)) ?? AttributedString(text)
    }
    var body: some View { Text(attributed).tint(EnchantTheme.accent) }
}
