//
//  IOSRootView.swift
//  iPhone：手表 mockup、陪伴值读写与 WCSession、提醒卡片。
//

import SwiftUI
import UserNotifications

struct IOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var companion: Double = 50
    @State private var reminders: [BolaReminder] = ReminderListStore.load()
    @State private var showAddReminder = false
    @State private var showDigestSheet = false
    @State private var digestBody = ""

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    watchMockup
                    companionControls
                    reminderSection
                }
                .padding()
            }
            .navigationTitle("BolaBola")
            .sheet(isPresented: $showAddReminder) {
                IOSAddReminderSheet { reminder in
                    reminders.append(reminder)
                    ReminderListStore.save(reminders)
                    Task { await BolaReminderUNScheduler.sync(reminders: reminders) }
                }
            }
            .sheet(isPresented: $showDigestSheet) {
                NavigationStack {
                    ScrollView {
                        Text(digestBody)
                            .font(.body)
                            .padding()
                    }
                    .navigationTitle("Bola 每日总结")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("好的") { showDigestSheet = false }
                        }
                    }
                }
            }
            .onAppear {
                consumeDigestNotificationIfNeeded()
                refreshCompanionFromAppGroup()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                BolaWCSessionCoordinator.shared.reapplyLatestReceivedContext()
                refreshCompanionFromAppGroup()
            }
            .task {
                BolaSharedDefaults.migrateStandardToGroupIfNeeded()
                ReminderBootstrap.ensureDefaults()
                reminders = ReminderListStore.load()
                refreshCompanionFromAppGroup()
                BolaWCSessionCoordinator.shared.onReceiveCompanionValue = { v in
                    Task { @MainActor in
                        companion = v
                    }
                }
                BolaWCSessionCoordinator.shared.activate()
                let center = UNUserNotificationCenter.current()
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                await BolaReminderUNScheduler.sync(reminders: reminders)
                let digest = DailyDigestStore.load()
                await DailyDigestUNScheduler.sync(config: digest)
                await DailyDigestRefresh.regenerateIfNeeded(companionValue: Int(companion.rounded()))
            }
        }
    }

    private func refreshCompanionFromAppGroup() {
        if bolaDefaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companion = bolaDefaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            companion = 50
        }
    }

    private func consumeDigestNotificationIfNeeded() {
        let d = bolaDefaults
        guard d.bool(forKey: BolaNotificationBridgeKeys.digestTapOpen) else { return }
        d.set(false, forKey: BolaNotificationBridgeKeys.digestTapOpen)
        digestBody = d.string(forKey: DailyDigestStorageKeys.lastDigestBody) ?? ""
        if !digestBody.isEmpty {
            showDigestSheet = true
        }
    }

    private var watchMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.linearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 180, height: 210)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                )
            VStack(spacing: 8) {
                Text("Bola")
                    .font(.caption.weight(.bold))
                Text("\(Int(companion.rounded()))")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("陪伴值")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, height: 170)
            .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var companionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("与手表同步")
                .font(.headline)
            HStack {
                Button("−") { adjustCompanion(-1) }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(Int(companion.rounded()))")
                    .font(.title2.monospacedDigit())
                Spacer()
                Button("+") { adjustCompanion(1) }
                    .buttonStyle(.bordered)
            }
            Text("修改后会通过 WatchConnectivity 推送到已配对的 Apple Watch。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("提醒")
                    .font(.headline)
                Spacer()
                Button("添加") { showAddReminder = true }
            }
            if reminders.isEmpty {
                Text("暂无提醒，点「添加」创建卡片式提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(reminders) { r in
                        reminderCard(r)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderCard(_ r: BolaReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(r.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(r.notificationBody)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Toggle("开", isOn: Binding(
                get: { r.isEnabled },
                set: { newVal in
                    guard let idx = reminders.firstIndex(where: { $0.id == r.id }) else { return }
                    var copy = reminders[idx]
                    copy.isEnabled = newVal
                    reminders[idx] = copy
                    ReminderListStore.save(reminders)
                    Task { await BolaReminderUNScheduler.sync(reminders: reminders) }
                }
            ))
            .labelsHidden()
            .font(.caption2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func adjustCompanion(_ delta: Int) {
        let next = min(100, max(0, Int(companion.rounded()) + delta))
        companion = Double(next)
        BolaWCSessionCoordinator.shared.pushCompanionValue(companion)
    }
}

private struct IOSAddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (BolaReminder) -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var hour = 9
    @State private var minute = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                TextField("通知正文", text: $bodyText, axis: .vertical)
                    .lineLimit(3 ... 6)
                Section("每日定时") {
                    Stepper("小时 \(hour)", value: $hour, in: 0 ... 23)
                    Stepper("分钟 \(minute)", value: $minute, in: 0 ... 59, step: 5)
                }
            }
            .navigationTitle("新提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "到点啦～" : bodyText
                        let r = BolaReminder(
                            title: t,
                            notificationBody: b,
                            schedule: .calendar(hour: hour, minute: minute, weekdays: [])
                        )
                        onSave(r)
                        dismiss()
                    }
                }
            }
        }
    }
}
