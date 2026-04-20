//
//  BolaDebugLog.swift
//  Shared — 运行期可开关的实时调试日志（仅 iPhone 上有 UI 展示）
//

import Foundation
import Combine

public final class BolaDebugLog: ObservableObject {
    public static let shared = BolaDebugLog()

    public enum Category: String, CaseIterable, Sendable {
        case petState   // 宠物情绪 / 核心状态
        case wc         // WCSession 生命周期
        case send       // 本机 → 对端 传输
        case recv       // 对端 → 本机 接收
        case chat       // 聊天增量
        case llm        // LLM 配置同步
        case speech     // 语音中继
        case command    // iPhone → Watch 交互指令
        case pending    // 排队 / 重试
        case meal       // meal slot / record / feed / auto-feed
        case error
        case info

        /// 用于 UI 标签上的短展示
        public var short: String {
            switch self {
            case .petState: return "PET"
            case .wc:       return "WC"
            case .send:     return "SEND"
            case .recv:     return "RECV"
            case .chat:     return "CHAT"
            case .llm:      return "LLM"
            case .speech:   return "SPCH"
            case .command:  return "CMD"
            case .pending:  return "PEND"
            case .meal:     return "MEAL"
            case .error:    return "ERR"
            case .info:     return "INFO"
            }
        }
    }

    public enum Source: String, Sendable {
        case iOS
        case watch
    }

    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let source: Source
        public let category: Category
        public let message: String
    }

    /// 单一持久化开关；关闭时 `log` 立即返回（不分配 Entry，不触发 Published）。
    @Published public var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @Published public private(set) var entries: [Entry] = []

    private let maxEntries = 500
    private static let enabledKey = "bola_debug_log_enabled_v1"

    private static var currentSource: Source {
        #if os(watchOS)
        return .watch
        #else
        return .iOS
        #endif
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// 从任意线程调用。关闭时零开销（只读一个 Bool 立即返回）。
    public func log(_ category: Category, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            source: Self.currentSource,
            category: category,
            message: message()
        )
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.append(entry)
            }
        }
    }

    public func clear() {
        if Thread.isMainThread {
            entries.removeAll()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.entries.removeAll()
            }
        }
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

// MARK: - 便捷导出

public extension BolaDebugLog {
    /// 生成一段可复制到剪贴板 / 邮件的纯文本快照（倒序：新的在上）。
    func exportPlainText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return entries
            .reversed()
            .map { e in
                let time = formatter.string(from: e.timestamp)
                let src = e.source == .iOS ? "📱" : "⌚️"
                return "\(time) \(src) [\(e.category.short)] \(e.message)"
            }
            .joined(separator: "\n")
    }
}
