import Foundation

/// Resolve computed strings through the same catalog as SwiftUI's literal labels.
/// Language choice belongs to the system; records, date keys and user notes stay unchanged.
enum L10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
    /// Translate only our own source markers; HealthKit provider names remain verbatim.
    static func heartSource(_ source: String) -> String {
        switch source {
        case "Apple Watch · 本次健康会话", "演示数据": return text(source)
        default: return source
        }
    }
}
