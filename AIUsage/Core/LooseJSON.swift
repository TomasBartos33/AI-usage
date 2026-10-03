import Foundation

/// Tiny helpers for reading untyped JSON defensively. Local tool formats are
/// undocumented and change between versions, so parsers extract individual
/// fields and tolerate anything missing or mistyped instead of decoding a
/// rigid schema.
enum LooseJSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
    }

    static func object<S: StringProtocol>(line: S) -> [String: Any]? {
        guard let first = line.first(where: { !$0.isWhitespace }), first == "{" else { return nil }
        return object(Data(line.utf8))
    }

    static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    static func string(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber:
            // JSONSerialization represents booleans as NSNumber too.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? d : nil
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        guard let d = double(value), d >= Double(Int.min), d <= Double(Int.max) else { return nil }
        return Int(d)
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// Accepts Unix seconds, Unix milliseconds or ISO-8601 strings.
    static func date(_ value: Any?) -> Date? {
        if let s = value as? String {
            return parseISO8601(s) ?? Double(s).flatMap(dateFromEpoch)
        }
        return double(value).flatMap(dateFromEpoch)
    }

    static func dateFromEpoch(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        // Anything above ~year 5000 in seconds is almost certainly milliseconds.
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        // Python-style timestamps with microseconds (6 fractional digits) and offsets.
        if let regex = try? NSRegularExpression(pattern: #"(\.\d{3})\d+"#),
           case let range = NSRange(string.startIndex..., in: string),
           regex.firstMatch(in: string, range: range) != nil {
            let trimmed = regex.stringByReplacingMatches(in: string, range: range, withTemplate: "$1")
            return withFraction.date(from: trimmed)
        }
        return nil
    }
}

/// Reads the tail of a potentially large append-only file (JSONL logs)
/// without loading the whole file.
enum FileTail {
    /// Returns complete lines from the last `maxBytes` of the file, oldest first.
    static func lines(of url: URL, maxBytes: Int) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            // Read one byte before `start` to know whether the first line is complete.
            try handle.seek(toOffset: start > 0 ? start - 1 : 0)
            guard var data = try handle.readToEnd() else { return [] }
            var firstLineIsPartial = false
            if start > 0, let first = data.first {
                firstLineIsPartial = first != 0x0A
                data.removeFirst()
            }
            let text = String(decoding: data, as: UTF8.self)
            var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if firstLineIsPartial, !lines.isEmpty { lines.removeFirst() }
            return lines
        } catch {
            return nil
        }
    }
}
