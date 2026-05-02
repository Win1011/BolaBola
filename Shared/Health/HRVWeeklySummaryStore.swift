//
//  HRVWeeklySummaryStore.swift
//  最近 7 天 HRV 摘要缓存；只保存聚合值，不保存 HealthKit 原始样本。
//

import Foundation

public struct HRVDailySummary: Codable, Equatable, Sendable {
    public var day: String
    public var sampleCount: Int
    public var averageSDNNMilliseconds: Double

    public init(day: String, sampleCount: Int, averageSDNNMilliseconds: Double) {
        self.day = day
        self.sampleCount = sampleCount
        self.averageSDNNMilliseconds = averageSDNNMilliseconds
    }
}

public enum HRVTrendStatus: String, Codable, Sendable {
    case insufficientData
    case belowBaseline
    case nearBaseline
    case aboveBaseline
    case variable

    public var displayName: String {
        switch self {
        case .insufficientData: return "数据不足"
        case .belowBaseline: return "低于近期基线"
        case .nearBaseline: return "接近近期基线"
        case .aboveBaseline: return "高于近期基线"
        case .variable: return "波动较大"
        }
    }
}

// TODO(HRV 严谨版): 后续基于更长个人基线，并结合用户年龄、性别、采样时段、
// Apple Watch 采样条件与权威资料重新设计判定。当前版本只做非诊断式趋势参考。
public struct HRVWeeklySummary: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var days: [HRVDailySummary]
    public var sevenDayAverageSDNNMilliseconds: Double?
    public var latestDayAverageSDNNMilliseconds: Double?
    public var latestDeviationFromBaselinePercent: Double?
    public var dataCompleteness: Double
    public var status: HRVTrendStatus

    public init(
        generatedAt: Date,
        days: [HRVDailySummary],
        sevenDayAverageSDNNMilliseconds: Double?,
        latestDayAverageSDNNMilliseconds: Double?,
        latestDeviationFromBaselinePercent: Double?,
        dataCompleteness: Double,
        status: HRVTrendStatus
    ) {
        self.generatedAt = generatedAt
        self.days = days
        self.sevenDayAverageSDNNMilliseconds = sevenDayAverageSDNNMilliseconds
        self.latestDayAverageSDNNMilliseconds = latestDayAverageSDNNMilliseconds
        self.latestDeviationFromBaselinePercent = latestDeviationFromBaselinePercent
        self.dataCompleteness = dataCompleteness
        self.status = status
    }

    public var promptText: String {
        guard status != .insufficientData,
              let sevenDayAverageSDNNMilliseconds,
              let latestDayAverageSDNNMilliseconds else {
            return """
            最近 7 天 HRV 摘要：数据不足，不能判断趋势。请提醒用户 Apple Watch 佩戴、健康授权和样本数量会影响结果；不要诊断。
            """
        }

        let deviationText: String
        if let latestDeviationFromBaselinePercent {
            deviationText = String(format: "%.0f%%", latestDeviationFromBaselinePercent)
        } else {
            deviationText = "未知"
        }
        let dayLines = days.map {
            "\($0.day): \(String(format: "%.0f", $0.averageSDNNMilliseconds))ms / \($0.sampleCount) 个样本"
        }.joined(separator: "；")
        return """
        最近 7 天 HRV 摘要（Apple HealthKit SDNN，毫秒，非医疗诊断）：状态=\(status.displayName)；7日均值=\(String(format: "%.0f", sevenDayAverageSDNNMilliseconds))ms；最近有数据日均值=\(String(format: "%.0f", latestDayAverageSDNNMilliseconds))ms；相对近期基线偏离=\(deviationText)；数据完整度=\(String(format: "%.0f%%", dataCompleteness * 100))。日级摘要：\(dayLines)。回答时必须使用“参考、趋势、可能”等措辞，不能给医疗诊断或固定年龄性别阈值结论。
        """
    }
}

public enum HRVWeeklySummaryStore {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> HRVWeeklySummary? {
        guard let data = defaults.data(forKey: CompanionPersistenceKeys.hrvWeeklySummaryJSON) else {
            return nil
        }
        return try? decoder.decode(HRVWeeklySummary.self, from: data)
    }

    public static func save(_ summary: HRVWeeklySummary, to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard let data = try? encoder.encode(summary) else { return }
        defaults.set(data, forKey: CompanionPersistenceKeys.hrvWeeklySummaryJSON)
    }

    public static func clear(from defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        defaults.removeObject(forKey: CompanionPersistenceKeys.hrvWeeklySummaryJSON)
    }
}
