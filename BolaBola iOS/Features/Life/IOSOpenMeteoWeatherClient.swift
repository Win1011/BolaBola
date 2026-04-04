//
//  IOSOpenMeteoWeatherClient.swift
//  无密钥：api.open-meteo.com
//

import Foundation

struct OpenMeteoCurrentWeather: Equatable {
    var temperatureC: Double
    /// WMO weather code
    var weatherCode: Int
}

enum IOSOpenMeteoWeatherClient {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    static func fetchCurrent(latitude: Double, longitude: Double) async throws -> OpenMeteoCurrentWeather {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = c.url else {
            throw URLError(.badURL)
        }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let t = decoded.current?.temperature_2m, let code = decoded.current?.weather_code else {
            throw URLError(.cannotDecodeContentData)
        }
        return OpenMeteoCurrentWeather(temperatureC: t, weatherCode: code)
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let weather_code: Int?
        }
        let current: Current?
    }
}

enum WeatherCodeMapper {
    static func systemImageName(code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51 ... 57: return "cloud.drizzle.fill"
        case 61 ... 67: return "cloud.rain.fill"
        case 71 ... 77: return "cloud.snow.fill"
        case 80 ... 82: return "cloud.heavyrain.fill"
        case 95 ... 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// WMO `weather_code` → emoji（分段与 `systemImageName` 一致）。
    static func emoji(code: Int) -> String {
        switch code {
        case 0: return "☀️"
        case 1: return "🌤️"
        case 2: return "⛅️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51 ... 55: return "🌦️"
        case 56, 57: return "🌨️"
        case 61 ... 65: return "🌧️"
        case 66, 67: return "🌨️"
        case 71 ... 77: return "❄️"
        case 80 ... 82: return "🌧️"
        case 95 ... 99: return "⛈️"
        default: return "☁️"
        }
    }

    /// WMO `weather_code` → 中文短句（与 `emoji` 分段一致）。
    static func chineseShortSummary(code: Int) -> String {
        switch code {
        case 0: return "晴朗"
        case 1: return "少云"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51 ... 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61 ... 65: return "雨"
        case 66, 67: return "冻雨"
        case 71 ... 77: return "雪"
        case 80 ... 82: return "阵雨"
        case 95 ... 99: return "雷暴"
        default: return "多云"
        }
    }
}
