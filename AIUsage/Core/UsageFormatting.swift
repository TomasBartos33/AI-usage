import Foundation

/// Pure formatting helpers shared by the menu bar and the detail panel.
enum UsageFormatting {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Compact countdown: "2h14m", "45m", "3d4h", "<1m".
    static func compactCountdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return hours % 24 == 0 ? "\(days)d" : "\(days)d\(hours % 24)h" }
        if hours > 0 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h\(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// "resets in 2h 14m at 18:42" for near resets, "resets Sun 18:42" for distant ones.
    static func resetDescription(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "reset \(relativePast(date, now: now))" }
        if interval < 24 * 3600 {
            let minutes = Int(interval / 60)
            let h = minutes / 60, m = minutes % 60
            let clock = DateFormatter()
            clock.calendar = calendar
            clock.timeZone = calendar.timeZone
            clock.locale = Locale(identifier: "en_US_POSIX")
            clock.dateFormat = "HH:mm"
            let at = " at \(clock.string(from: date))"
            if h == 0 { return (m == 0 ? "resets in <1m" : "resets in \(m)m") + at }
            return (m == 0 ? "resets in \(h)h" : "resets in \(h)h \(m)m") + at
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(interval < 6 * 24 * 3600 ? "EEE jj:mm" : "MMM d jj:mm")
        return "resets \(formatter.string(from: date))"
    }

    /// "now", "5 min ago", "3 h ago", "2 days ago".
    static func relativePast(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) days ago"
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000:
            let k = Double(count) / 1_000
            return k < 10 ? String(format: "%.1fK", k) : "\(Int(k.rounded()))K"
        default:
            return String(format: "%.2fM", Double(count) / 1_000_000)
        }
    }

    static func usd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// Shortens a path for display: "~/Documents/x" or just the last component.
    static func projectName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }
}
