//
//  WatchFaceSlotsConfiguration.swift
//  iPhone 主界面「自定义表盘」三槽（左上 / 左下 / 右下）；同步到手表后在 App 内叠层展示（非系统表盘 API）。
//

import Foundation

/// 单槽可放置的组件类型（手表端按类型拉取数据）。
public enum WatchFaceComplicationKind: String, Codable, CaseIterable, Sendable {
    case none
    case heartRate
    case weather
    case steps

    public var displayName: String {
        switch self {
        case .none: return "空"
        case .heartRate: return "心率"
        case .weather: return "天气"
        case .steps: return "步数"
        }
    }

    public static var paletteKinds: [WatchFaceComplicationKind] {
        [.heartRate, .weather, .steps]
    }
}

/// 三个固定角落在工程与 UI 中一一对应（与表镜内归一化坐标一致）。
public enum WatchFaceSlotPosition: String, Codable, CaseIterable, Sendable {
    case topLeft
    case bottomLeft
    case bottomRight
}

public struct WatchFaceSlotsConfiguration: Codable, Equatable, Sendable {
    public var topLeft: WatchFaceComplicationKind
    public var bottomLeft: WatchFaceComplicationKind
    public var bottomRight: WatchFaceComplicationKind

    public init(topLeft: WatchFaceComplicationKind, bottomLeft: WatchFaceComplicationKind, bottomRight: WatchFaceComplicationKind) {
        self.topLeft = topLeft
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    public static var `default`: WatchFaceSlotsConfiguration {
        WatchFaceSlotsConfiguration(topLeft: .none, bottomLeft: .none, bottomRight: .none)
    }

    public func kind(at position: WatchFaceSlotPosition) -> WatchFaceComplicationKind {
        switch position {
        case .topLeft: return topLeft
        case .bottomLeft: return bottomLeft
        case .bottomRight: return bottomRight
        }
    }

    public mutating func set(_ position: WatchFaceSlotPosition, kind: WatchFaceComplicationKind) {
        switch position {
        case .topLeft: topLeft = kind
        case .bottomLeft: bottomLeft = kind
        case .bottomRight: bottomRight = kind
        }
    }

    enum CodingKeys: String, CodingKey {
        case topLeft
        case bottomLeft
        case bottomRight
        case kinds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decode([WatchFaceComplicationKind].self, forKey: .kinds) {
            topLeft = arr.indices.contains(0) ? arr[0] : .none
            bottomLeft = arr.indices.contains(1) ? arr[1] : .none
            bottomRight = arr.indices.contains(2) ? arr[2] : .none
        } else {
            topLeft = try c.decode(WatchFaceComplicationKind.self, forKey: .topLeft)
            bottomLeft = try c.decode(WatchFaceComplicationKind.self, forKey: .bottomLeft)
            bottomRight = try c.decode(WatchFaceComplicationKind.self, forKey: .bottomRight)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(topLeft, forKey: .topLeft)
        try c.encode(bottomLeft, forKey: .bottomLeft)
        try c.encode(bottomRight, forKey: .bottomRight)
    }
}

public enum WatchFaceSlotsStore {
    private static let defaultsKey = "bola_watch_face_slots_v1"

    public static func load() -> WatchFaceSlotsConfiguration {
        let d = BolaSharedDefaults.resolved()
        guard let data = d.data(forKey: defaultsKey),
              let c = try? JSONDecoder().decode(WatchFaceSlotsConfiguration.self, from: data) else {
            return .default
        }
        return c
    }

    public static func save(_ config: WatchFaceSlotsConfiguration) {
        let d = BolaSharedDefaults.resolved()
        if let data = try? JSONEncoder().encode(config) {
            d.set(data, forKey: defaultsKey)
        }
    }
}

extension Notification.Name {
    /// 手表端收到 iPhone 下发的表盘槽/称号等主屏 payload 并已写入 defaults。
    public static let bolaWatchHomeScreenPayloadDidUpdate = Notification.Name("bolaWatchHomeScreenPayloadDidUpdate")
}
