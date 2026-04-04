//
//  IOSWeatherConditionEmoji.swift
//  WeatherKit `WeatherCondition` → 生活卡用 emoji（与系统语义大致对应）。
//

import WeatherKit

enum IOSWeatherConditionEmoji {
    static func emoji(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "☀️"
        case .mostlyClear: return "🌤️"
        case .partlyCloudy: return "⛅️"
        case .mostlyCloudy: return "🌥️"
        case .cloudy: return "☁️"
        case .foggy, .haze, .smoky: return "🌫️"
        case .breezy, .windy: return "💨"
        case .blowingDust: return "🌪️"
        case .drizzle: return "🌦️"
        case .rain: return "🌧️"
        case .heavyRain: return "🌧️"
        case .sunShowers: return "🌦️"
        case .isolatedThunderstorms: return "🌩️"
        case .scatteredThunderstorms, .strongStorms, .thunderstorms: return "⛈️"
        case .hot: return "🌡️"
        case .frigid: return "🥶"
        case .flurries, .sunFlurries: return "🌨️"
        case .snow: return "❄️"
        case .heavySnow, .blizzard, .blowingSnow: return "❄️"
        case .sleet, .wintryMix: return "🌨️"
        case .freezingDrizzle, .freezingRain: return "🌨️"
        case .hail: return "🌨️"
        case .hurricane, .tropicalStorm: return "🌀"
        @unknown default:
            return "🌤️"
        }
    }

    /// 与 `emoji(for:)` 对应的中文短句（生活卡天气状况文案）。
    static func chineseSummary(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "晴朗"
        case .mostlyClear: return "大部晴朗"
        case .partlyCloudy: return "局部多云"
        case .mostlyCloudy: return "大部多云"
        case .cloudy: return "阴"
        case .foggy: return "雾"
        case .haze: return "霾"
        case .smoky: return "烟霾"
        case .breezy: return "微风"
        case .windy: return "大风"
        case .blowingDust: return "沙尘"
        case .drizzle: return "毛毛雨"
        case .rain: return "雨"
        case .heavyRain: return "大雨"
        case .sunShowers: return "阵雨"
        case .isolatedThunderstorms: return "局部雷雨"
        case .scatteredThunderstorms: return "分散雷雨"
        case .strongStorms: return "强雷暴"
        case .thunderstorms: return "雷阵雨"
        case .hot: return "炎热"
        case .frigid: return "严寒"
        case .flurries: return "小阵雪"
        case .sunFlurries: return "阵雪"
        case .snow: return "雪"
        case .heavySnow: return "大雪"
        case .blizzard: return "暴雪"
        case .blowingSnow: return "吹雪"
        case .sleet: return "雨夹雪"
        case .wintryMix: return "雨雪混合"
        case .freezingDrizzle: return "冻毛毛雨"
        case .freezingRain: return "冻雨"
        case .hail: return "冰雹"
        case .hurricane: return "飓风"
        case .tropicalStorm: return "热带风暴"
        @unknown default:
            return "天气"
        }
    }
}
