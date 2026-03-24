//
//  WatchChatHistoryView.swift
//  按自然日分组的对话记录（与 iPhone 试聊共用 App Group 中的 ChatHistoryStore）
//

import SwiftUI

struct WatchChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [ChatTurn] = []

    private var grouped: [(day: Date, items: [ChatTurn])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: turns) { cal.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted(by: >).compactMap { day in
            guard let items = byDay[day] else { return nil }
            return (day, items.sorted { $0.createdAt < $1.createdAt })
        }
    }

    var body: some View {
        List {
            if turns.isEmpty {
                Section {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.items) { turn in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(turn.role == "user" ? "你" : "Bola")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(turn.content)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(daySectionTitle(for: group.day))
                            .font(.caption2)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    ChatHistoryStore.clear()
                    reload()
                } label: {
                    Text("清空记录")
                        .font(.caption)
                }
                .disabled(turns.isEmpty)
            }
        }
        .navigationTitle("对话记录")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .bolaChatHistoryDidMerge)) { _ in
            reload()
        }
    }

    private func reload() {
        turns = ChatHistoryStore.load(from: BolaSharedDefaults.resolved())
    }

    private func daySectionTitle(for startOfDay: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(startOfDay) { return "今天" }
        if cal.isDateInYesterday(startOfDay) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh-Hans")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: startOfDay)
    }
}
