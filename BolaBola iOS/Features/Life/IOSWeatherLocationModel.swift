//
//  IOSWeatherLocationModel.swift
//

import Combine
import CoreLocation
import SwiftUI

@MainActor
final class IOSWeatherLocationModel: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var weather: OpenMeteoCurrentWeather?
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
            weather = try await IOSOpenMeteoWeatherClient.fetchCurrent(latitude: lat, longitude: lon)
        } catch {
            lastError = "无法获取天气"
            weather = nil
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
