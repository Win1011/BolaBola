//
//  IOSSettingsView.swift
//

import SwiftUI
import UIKit
import UserNotifications

/// 设置列表（由根视图以 Sheet + `NavigationStack` 呈现，或单独再包一层导航栈）。
struct IOSSettingsListView: View {
    /// Sheet 里需要「完成」关闭；仅 `NavigationStack` 包一层时可关。
    var includeDismissToolbar: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmResetLifeRecords = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    IOSAPISettingsPage()
                } label: {
                    Label("对话 API", systemImage: "key.horizontal.fill")
                }
            } header: {
                Text("连接")
            } footer: {
                Text("密钥与中转地址保存在本机钥匙串，并可同步到 Apple Watch。")
            }

            Section {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(notificationStatusLabel)
                        .foregroundStyle(.secondary)
                }
                Button("前往系统设置…") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("再次请求通知授权") {
                    Task { @MainActor in
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        await refreshNotificationStatus()
                    }
                }
            } header: {
                Text("通知")
            } footer: {
                Text("「尚未询问」表示还没在系统弹窗里选择过是否允许通知，与健康数据无关；健康在 设置 › 隐私与安全性 › 健康。")
                    .font(.caption)
            }

            Section {
                Button("恢复默认生活卡片…", role: .destructive) {
                    confirmResetLifeRecords = true
                }
            } header: {
                Text("生活记录")
            } footer: {
                Text("删除除「天气」外的所有生活卡片，用于清理测试数据；操作后无法撤销。")
            }

            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("BolaBola")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("关于")
            } footer: {
                Text("性格与用户档案等功能将后续在此扩展。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if includeDismissToolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await refreshNotificationStatus()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
        }
        .confirmationDialog(
            "将删除除「天气」外的所有生活卡片，且无法撤销。",
            isPresented: $confirmResetLifeRecords,
            titleVisibility: .visible
        ) {
            Button("恢复默认", role: .destructive) {
                LifeRecordListStore.resetToDefaultDeck()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已拒绝"
        // 与「健康」无关：表示系统尚未记录你对通知的选择（未弹窗或从未点过允许/拒绝）。
        case .notDetermined: return "尚未询问"
        @unknown default: return "未知"
        }
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = s.authorizationStatus
    }
}

/// 独立打开设置时使用的带导航栈包装（预览/深链等）。
struct IOSSettingsView: View {
    var body: some View {
        NavigationStack {
            IOSSettingsListView(includeDismissToolbar: false)
        }
    }
}
