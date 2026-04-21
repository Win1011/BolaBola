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
        let lifeRecords = LifeRecordListStore.load(from: defaults)
        let dayKey = Self.dayKey(for: date)
        let temperature = roundedTemperature(weather.temperatureC)

        if !hasDailyWeatherEntry(on: date, entries: entries) {
            BolaDiaryStore.append(
                BolaDiaryEntry(
                    createdAt: date,
                    title: "今天天气",
                    summary: "主人今天这边是\(weather.conditionText)，大概\(temperature)度。",
                    emoji: weather.emoji,
                    sourceText: "\(dailyPrefix)\(dayKey):\(weather.conditionText):\(temperature)"
                ),
                to: defaults
            )
        }

        if !hasDailyWeatherLifeRecord(on: date, records: lifeRecords) {
            var updatedRecords = lifeRecords
            updatedRecords.append(
                LifeRecordCard(
                    kind: .weather,
                    title: dailyWeatherLifeTitle,
                    subtitle: "\(weather.conditionText) · \(temperature)°C",
                    detailNote: "主人今天这边是\(weather.conditionText)，大概\(temperature)度。",
                    iconEmoji: weather.emoji,
                    createdAt: date
                )
            )
            LifeRecordListStore.save(updatedRecords, to: defaults)
        }

        guard shouldRecordChange(for: weather, at: date, entries: entries) else { return }
        BolaDiaryStore.append(
            BolaDiaryEntry(
                createdAt: date,
                title: "天气变化",
                summary: "Bola发现今天的天气变成了\(weather.conditionText)，现在大概\(temperature)度。",
                emoji: weather.emoji,
                sourceText: "\(changePrefix)\(dayKey):\(weather.conditionText):\(temperature)"
            ),
            to: defaults
        )

        if !hasMatchingWeatherChangeRecord(on: date, weather: weather, records: LifeRecordListStore.load(from: defaults)) {
            var updatedRecords = LifeRecordListStore.load(from: defaults)
            updatedRecords.append(
                LifeRecordCard(
                    kind: .weather,
                    title: changedWeatherLifeTitle,
                    subtitle: "\(weather.conditionText) · \(temperature)°C",
                    detailNote: "Bola发现今天的天气变成了\(weather.conditionText)，现在大概\(temperature)度。",
                    iconEmoji: weather.emoji,
                    createdAt: date
                )
            )
            LifeRecordListStore.save(updatedRecords, to: defaults)
        }
    }

    static func syncLifeRecordsFromDiary(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let diaryEntries = BolaDiaryStore.load(from: defaults)
        var records = LifeRecordListStore.load(from: defaults)
        var didChange = false

        for entry in diaryEntries.sorted(by: { $0.createdAt < $1.createdAt }) {
            if entry.sourceText.hasPrefix(dailyPrefix) {
                if !records.contains(where: {
                    $0.kind == .weather &&
                        $0.title == dailyWeatherLifeTitle &&
                        Calendar.current.isDate($0.createdAt, inSameDayAs: entry.createdAt)
                }) {
                    records.append(
                        LifeRecordCard(
                            kind: .weather,
                            title: dailyWeatherLifeTitle,
                            subtitle: weatherSubtitle(from: entry),
                            detailNote: entry.summary,
                            iconEmoji: entry.emoji,
                            createdAt: entry.createdAt
                        )
                    )
                    didChange = true
                }
            } else if entry.sourceText.hasPrefix(changePrefix) {
                let subtitle = weatherSubtitle(from: entry)
                if !records.contains(where: {
                    $0.kind == .weather &&
                        $0.title == changedWeatherLifeTitle &&
                        $0.subtitle == subtitle &&
                        Calendar.current.isDate($0.createdAt, inSameDayAs: entry.createdAt)
                }) {
                    records.append(
                        LifeRecordCard(
                            kind: .weather,
                            title: changedWeatherLifeTitle,
                            subtitle: subtitle,
                            detailNote: entry.summary,
                            iconEmoji: entry.emoji,
                            createdAt: entry.createdAt
                        )
                    )
                    didChange = true
                }
            }
        }

        if didChange {
            LifeRecordListStore.save(records, to: defaults)
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

    private static func hasDailyWeatherLifeRecord(on date: Date, records: [LifeRecordCard]) -> Bool {
        records.contains {
            $0.kind == .weather &&
                $0.title == dailyWeatherLifeTitle &&
                Calendar.current.isDate($0.createdAt, inSameDayAs: date)
        }
    }

    private static func hasMatchingWeatherChangeRecord(
        on date: Date,
        weather: BolaLifePageWeather,
        records: [LifeRecordCard]
    ) -> Bool {
        let expectedSubtitle = "\(weather.conditionText) · \(roundedTemperature(weather.temperatureC))°C"
        return records.contains {
            $0.kind == .weather &&
                $0.title == changedWeatherLifeTitle &&
                $0.subtitle == expectedSubtitle &&
                Calendar.current.isDate($0.createdAt, inSameDayAs: date)
        }
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

    private static func weatherSubtitle(from entry: BolaDiaryEntry) -> String? {
        guard let condition = parseCondition(from: entry.sourceText),
              let temperature = parseTemperature(from: entry.sourceText) else {
            return nil
        }
        return "\(condition) · \(temperature)°C"
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
