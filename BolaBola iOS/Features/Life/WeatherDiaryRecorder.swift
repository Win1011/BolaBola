//
//  WeatherDiaryRecorder.swift
//

import Foundation

enum WeatherDiaryRecorder {
    private static let dailyPrefix = "weather:daily:"
    private static let changePrefix = "weather:change:"
    static let dailyWeatherLifeTitle = "今天天气"
    static let changedWeatherLifeTitle = "天气变化"

    static func recordIfNeeded(
        weather: BolaLifePageWeather,
        at date: Date = Date(),
        defaults: UserDefaults = BolaSharedDefaults.resolved()
    ) {
        guard shouldRecordDailyWeather(at: date) else { return }

        let entries = BolaDiaryStore.load(from: defaults)
        let dayKey = Self.dayKey(for: date)
        let temperature = roundedTemperature(weather.temperatureC)

        if !hasDailyWeatherEntry(on: date, entries: entries) {
            let userLabel = BolaTimelineRecorder.resolvedUserDisplayName()
            BolaDiaryStore.append(
                BolaDiaryEntry(
                    createdAt: date,
                    title: dailyWeatherLifeTitle,
                    summary: "\(userLabel)今天这边是\(weather.conditionText)，大概\(temperature)度。",
                    emoji: weather.emoji,
                    sourceText: "\(dailyPrefix)\(dayKey):\(weather.conditionText):\(temperature)"
                ),
                to: defaults
            )
        }

        guard shouldRecordChange(for: weather, at: date, entries: entries) else { return }
        let petName = CompanionDisplayNameStore.resolved(using: defaults)
        BolaDiaryStore.append(
            BolaDiaryEntry(
                createdAt: date,
                title: changedWeatherLifeTitle,
                summary: "\(petName)发现今天的天气变成了\(weather.conditionText)，现在大概\(temperature)度。",
                emoji: weather.emoji,
                sourceText: "\(changePrefix)\(dayKey):\(weather.conditionText):\(temperature)"
            ),
            to: defaults
        )
    }

    static func syncLifeRecordsFromDiary(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let records = LifeRecordListStore.load(from: defaults)
        let filteredRecords = records.filter { $0.kind != .weather }
        if filteredRecords.count != records.count {
            LifeRecordListStore.save(filteredRecords, to: defaults)
        }
    }

    private static func hasDailyWeatherEntry(on date: Date, entries: [BolaDiaryEntry]) -> Bool {
        entries.contains { entry in
            entry.sourceText.hasPrefix(dailyPrefix) &&
                Calendar.current.isDate(entry.createdAt, inSameDayAs: date)
        }
    }

    private static func shouldRecordChange(
        for weather: BolaLifePageWeather,
        at date: Date,
        entries: [BolaDiaryEntry]
    ) -> Bool {
        let todayWeatherEntries = entries
            .filter {
                ($0.sourceText.hasPrefix(dailyPrefix) || $0.sourceText.hasPrefix(changePrefix)) &&
                    Calendar.current.isDate($0.createdAt, inSameDayAs: date)
            }
            .sorted { $0.createdAt > $1.createdAt }

        guard let latest = todayWeatherEntries.first else { return false }
        guard date.timeIntervalSince(latest.createdAt) >= 30 * 60 else { return false }

        let latestCondition = parseCondition(from: latest.sourceText)
        let latestTemperature = parseTemperature(from: latest.sourceText)

        if let latestCondition, latestCondition != weather.conditionText {
            return true
        }

        if let latestTemperature, abs(latestTemperature - roundedTemperature(weather.temperatureC)) >= 5 {
            return true
        }

        return false
    }

    private static func shouldRecordDailyWeather(at date: Date) -> Bool {
        Calendar.current.component(.hour, from: date) >= 8
    }

    private static func parseCondition(from sourceText: String) -> String? {
        let parts = sourceText.components(separatedBy: ":")
        guard parts.count >= 4 else { return nil }
        return parts[3]
    }

    private static func parseTemperature(from sourceText: String) -> Int? {
        let parts = sourceText.components(separatedBy: ":")
        guard let last = parts.last else { return nil }
        return Int(last)
    }

    private static func roundedTemperature(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
