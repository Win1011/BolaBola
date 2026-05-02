//
//  IOSPrivacySettingsPage.swift
//

import SwiftUI

struct IOSPrivacySettingsPage: View {
    @State private var chatCount: Int = ChatHistoryStore.load().count
    @State private var diaryCount: Int = BolaDiaryStore.load().count

    @State private var confirmClearChat = false
    @State private var confirmClearDiary = false
    @State private var confirmClearAll = false

    var body: some View {
        List {
            // MARK: 数据说明
            Section {
                dataRow(icon: "iphone", label: "存储位置", value: "仅在本机")
                dataRow(icon: "heart.fill", label: "健康数据", value: "只读，不上传")
                dataRow(icon: "lock.fill", label: "API 密钥", value: "本机钥匙串")
                dataRow(icon: "arrow.triangle.2.circlepath", label: "Watch 同步", value: "本机 WatchConnectivity")
            } header: {
                Text("数据说明")
            } footer: {
                Text("BolaBola 的所有数据均存储在你的设备本地。健康数据通过 HealthKit 只读取，从不上传到服务器。登录账户仅用于 AI 对话接口，不同步任何本地健康或日记内容。")
            }

            // MARK: 聊天记录
            Section {
                HStack {
                    Text("聊天记录")
                    Spacer()
                    Text("\(chatCount) 条")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("清除聊天记录…", role: .destructive) {
                    confirmClearChat = true
                }
                .disabled(chatCount == 0)
            } header: {
                Text("聊天")
            } footer: {
                Text("Bola 在手表和 iPhone 上的对话记录，最多保留 24 条。清除后无法恢复。")
            }

            // MARK: 日记
            Section {
                HStack {
                    Text("日记条目")
                    Spacer()
                    Text("\(diaryCount) 条")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("清除日记…", role: .destructive) {
                    confirmClearDiary = true
                }
                .disabled(diaryCount == 0)
            } header: {
                Text("日记")
            } footer: {
                Text("由 Bola 从对话中提取的日记摘要，存储在本机。清除后无法恢复。")
            }

            // MARK: 清除全部
            Section {
                Button("清除所有 App 数据…", role: .destructive) {
                    confirmClearAll = true
                }
            } header: {
                Text("重置")
            } footer: {
                Text("清除聊天记录、日记、生活卡片、陪伴值、成长 XP 等全部本地数据，等同于重新安装。此操作不可撤销。")
            }
        }
        .navigationTitle("数据与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshCounts() }
        .confirmationDialog(
            "将清除所有聊天记录，且无法撤销。",
            isPresented: $confirmClearChat,
            titleVisibility: .visible
        ) {
            Button("清除聊天记录", role: .destructive) {
                ChatHistoryStore.save([])
                refreshCounts()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "将清除所有日记条目，且无法撤销。",
            isPresented: $confirmClearDiary,
            titleVisibility: .visible
        ) {
            Button("清除日记", role: .destructive) {
                BolaDiaryStore.save([])
                refreshCounts()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "将清除全部本地数据，包括聊天、日记、生活卡片、陪伴值和成长进度。此操作不可撤销。",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("清除所有数据", role: .destructive) {
                clearAllData()
                refreshCounts()
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func dataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private func refreshCounts() {
        chatCount = ChatHistoryStore.load().count
        diaryCount = BolaDiaryStore.load().count
    }

    private func clearAllData() {
        let defaults = BolaSharedDefaults.resolved()

        // 聊天 & 日记
        ChatHistoryStore.save([])
        BolaDiaryStore.save([])

        // 生活卡片
        LifeRecordListStore.resetToDefaultDeck()

        // 提醒
        ReminderListStore.save([])
        Task { await BolaReminderUNScheduler.sync(reminders: []) }

        // 陪伴值
        for key in CompanionPersistenceKeys.allCompanionKeys {
            defaults.removeObject(forKey: key)
        }

        // 成长 XP
        BolaGrowthStore.save(BolaGrowthState())
        BolaPersonalitySelectionStore.save(.default)

        // HRV 摘要
        defaults.removeObject(forKey: CompanionPersistenceKeys.hrvWeeklySummaryJSON)

        // 餐食记录（今日状态）
        defaults.removeObject(forKey: "bola_meal_records_v1")
        defaults.removeObject(forKey: "bola_meal_records_date_v1")

        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        NotificationCenter.default.post(name: .bolaGrowthStateDidChange, object: nil)
    }
}
