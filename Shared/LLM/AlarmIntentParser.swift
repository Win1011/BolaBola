//
//  AlarmIntentParser.swift
//

import Foundation

public enum AlarmIntentParser {

    public struct AlarmIntent: Sendable {
        public let fireDate: Date
    }

    /// Scans an LLM reply for `<<ALARM:{...}>>` tags.
    /// Returns the parsed intent and the reply with the tag stripped, or `nil` if no tag found.
    public static func parse(fromLLMReply reply: String) -> (intent: AlarmIntent, cleanedReply: String)? {
        guard let range = reply.range(of: #"<<ALARM:\{[^}]+\}>>"#, options: .regularExpression) else {
            return nil
        }

        let tag = String(reply[range])
        // Extract JSON between <<ALARM: and >>
        let jsonStart = tag.index(tag.startIndex, offsetBy: 8) // skip "<<ALARM:"
        let jsonEnd = tag.index(tag.endIndex, offsetBy: -2)     // skip ">>"
        let jsonString = String(tag[jsonStart..<jsonEnd])

        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let fireDate: Date
        if let minutes = dict["minutes"] as? Double, minutes > 0 {
            fireDate = Date().addingTimeInterval(minutes * 60)
        } else if let hour = dict["hour"] as? Int, let minute = dict["minute"] as? Int {
            fireDate = resolveNextOccurrence(hour: hour, minute: minute)
        } else {
            return nil
        }

        var cleaned = reply
        cleaned.removeSubrange(range)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return (AlarmIntent(fireDate: fireDate), cleaned)
    }

    /// Returns the next `Date` matching the given hour:minute (today if still ahead, otherwise tomorrow).
    private static func resolveNextOccurrence(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let candidate = cal.date(from: components), candidate > now {
            return candidate
        }
        // Already past — schedule for tomorrow
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        components = cal.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return cal.date(from: components) ?? tomorrow
    }
}
