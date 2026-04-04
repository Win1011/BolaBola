//
//  IOSWeatherLocationModel.swift
//

import Combine
import CoreLocation
import SwiftUI
import WeatherKit

/// 生活页天气卡展示用快照（摄氏温度 + SF Symbol 名供无障碍/一致性 + 对应 emoji + 状况短句）。
struct BolaLifePageWeather: Equatable, Sendable {
    var temperatureC: Double
    var systemImageName: String
    var emoji: String
    var conditionText: String
}

@MainActor
final class IOSWeatherLocationModel: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var weather: BolaLifePageWeather?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestAndFetch() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            fetchLocationThenWeather()
        case .denied, .restricted:
            lastError = "请在设置中允许位置权限以显示当地天气。"
        @unknown default:
            lastError = "无法获取位置。"
        }
    }

    private func fetchLocationThenWeather() {
        isLoading = true
        manager.requestLocation()
    }

    private func loadWeather(lat: Double, lon: Double) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            weather = try await Self.fetchWeatherBestEffort(latitude: lat, longitude: lon)
        } catch {
            lastError = "无法获取天气"
            weather = nil
        }
    }

    /// 优先 **WeatherKit**（`CurrentWeather.symbolName` 与系统天气一致）；失败时回退 **Open-Meteo**（无 WeatherKit 权益、模拟器、网络等原因）。
    private static func fetchWeatherBestEffort(latitude: Double, longitude: Double) async throws -> BolaLifePageWeather {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let snapshot = try await WeatherService.shared.weather(for: location)
            let cur = snapshot.currentWeather
            let celsius = cur.temperature.converted(to: .celsius).value
            return BolaLifePageWeather(
                temperatureC: celsius,
                systemImageName: cur.symbolName,
                emoji: IOSWeatherConditionEmoji.emoji(for: cur.condition),
                conditionText: IOSWeatherConditionEmoji.chineseSummary(for: cur.condition)
            )
        } catch {
            let om = try await IOSOpenMeteoWeatherClient.fetchCurrent(latitude: latitude, longitude: longitude)
            return BolaLifePageWeather(
                temperatureC: om.temperatureC,
                systemImageName: WeatherCodeMapper.systemImageName(code: om.weatherCode),
                emoji: WeatherCodeMapper.emoji(code: om.weatherCode),
                conditionText: WeatherCodeMapper.chineseShortSummary(code: om.weatherCode)
            )
        }
    }
}

extension IOSWeatherLocationModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            } else if manager.authorizationStatus == .denied {
                lastError = "请在设置中允许位置权限以显示当地天气。"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            await loadWeather(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            lastError = (error as NSError).localizedDescription
        }
    }
}
