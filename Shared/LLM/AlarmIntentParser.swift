//
//  AlarmIntentParser.swift
//

import Foundation

public enum AlarmIntentParser {

    public struct AlarmIntent: Sendable {
        public let schedule: BolaReminder.Schedule
        public let title: String?
        public let body: String?
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

        guard let schedule = parseSchedule(from: dict) else {
            return nil
        }

        var cleaned = reply
        cleaned.removeSubrange(range)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (dict["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            AlarmIntent(
                schedule: schedule,
                title: title?.isEmpty == false ? title : nil,
                body: body?.isEmpty == false ? body : nil
            ),
            cleaned
        )
    }

    private static func parseSchedule(from dict: [String: Any]) -> BolaReminder.Schedule? {
        let mode = (dict["mode"] as? String)?.lowercased()

        if mode == "interval" {
            if let minutes = dict["minutes"] as? Double, minutes > 0 {
                return .interval(max(60, minutes * 60))
            }
            if let hours = dict["hours"] as? Double, hours > 0 {
                return .interval(max(60, hours * 3600))
            }
        }

        if mode == "daily", let hour = dict["hour"] as? Int, let minute = dict["minute"] as? Int {
            return .calendar(hour: hour, minute: minute, weekdays: [])
        }

        if mode == "workweek", let hour = dict["hour"] as? Int, let minute = dict["minute"] as? Int {
            return .calendar(hour: hour, minute: minute, weekdays: [2, 3, 4, 5, 6])
        }

        if mode == "weekly",
           let hour = dict["hour"] as? Int,
           let minute = dict["minute"] as? Int,
           let weekdays = normalizedWeekdays(dict["weekdays"]) {
            return .calendar(hour: hour, minute: minute, weekdays: weekdays)
        }

        if let minutes = dict["minutes"] as? Double, minutes > 0, mode == nil || mode == "once" {
            return .once(Date().addingTimeInterval(minutes * 60))
        }

        if let hour = dict["hour"] as? Int, let minute = dict["minute"] as? Int {
            let dayOffset = dict["dayOffset"] as? Int ?? 0
            if mode == "once" || mode == nil {
                return .once(resolveOccurrence(hour: hour, minute: minute, dayOffset: dayOffset))
            }
        }

        return nil
    }

    private static func normalizedWeekdays(_ raw: Any?) -> [Int]? {
        guard let values = raw as? [Any] else { return nil }
        let weekdays = values.compactMap { value -> Int? in
            if let intValue = value as? Int, (1 ... 7).contains(intValue) { return intValue }
            if let stringValue = value as? String { return weekday(from: stringValue) }
            return nil
        }
        let unique = Array(Set(weekdays)).sorted()
        return unique.isEmpty ? nil : unique
    }

    private static func weekday(from raw: String) -> Int? {
        switch raw.lowercased() {
        case "1", "sun", "sunday", "周日", "星期日", "周天", "星期天": return 1
        case "2", "mon", "monday", "周一", "星期一": return 2
        case "3", "tue", "tuesday", "周二", "星期二": return 3
        case "4", "wed", "wednesday", "周三", "星期三": return 4
        case "5", "thu", "thursday", "周四", "星期四": return 5
        case "6", "fri", "friday", "周五", "星期五": return 6
        case "7", "sat", "saturday", "周六", "星期六": return 7
        default: return nil
        }
    }

    /// Returns the next `Date` matching the given hour:minute (today if still ahead, otherwise tomorrow).
    private static func resolveOccurrence(hour: Int, minute: Int, dayOffset: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        let baseDay = cal.date(byAdding: .day, value: max(0, dayOffset), to: now) ?? now
        var components = cal.dateComponents([.year, .month, .day], from: baseDay)
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let candidate = cal.date(from: components), candidate > now {
            return candidate
        }
        // Already past — schedule for tomorrow when dayOffset was not explicitly moved forward.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        components = cal.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return cal.date(from: components) ?? tomorrow
    }
}
