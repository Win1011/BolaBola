//
//  IOSDebugLogSheet.swift
//  BolaBola iOS
//
//  调试面板：实时显示宠物状态、WC 通信状态与最近日志。由 `IOSSettingsListView` 以 NavigationLink 打开。
//

import SwiftUI
import UIKit
import WatchConnectivity

struct IOSDebugLogSheet: View {
    @ObservedObject private var log = BolaDebugLog.shared
    @ObservedObject private var coord = BolaWCSessionCoordinator.shared

    @State private var selectedCategories: Set<BolaDebugLog.Category> = Set(BolaDebugLog.Category.allCases)
    @State private var autoScroll: Bool = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            summaryCard
                .padding(.horizontal)
                .padding(.top, 12)

            debugStateBar
                .padding(.horizontal)
                .padding(.vertical, 6)

            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            logList
        }
        .navigationTitle("调试日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("启用记录", isOn: $log.isEnabled)
                    Toggle("自动滚到底", isOn: $autoScroll)
                    Button("清空", role: .destructive) { log.clear() }
                    Button("复制到剪贴板") {
                        UIPasteboard.general.string = log.exportPlainText()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statusDot(log.isEnabled ? .green : .gray)
                Text(log.isEnabled ? "正在记录" : "未启用 — 右上角菜单打开")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(log.isEnabled ? .primary : .secondary)
                Spacer()
                Text("\(log.entries.count) / 500")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            petStateRow

            wcStateRow
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var petStateRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "pawprint.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("state=\(coord.currentPetCoreState.rawValue)")
                .font(.caption.monospacedDigit())
            Text("emo=\(coord.currentPetEmotionLabel)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var wcStateRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("activation=\(activationLabel(coord.debugActivationState))")
                Text("paired=\(boolBadge(coord.debugIsPaired))")
                Text("installed=\(boolBadge(coord.debugIsCounterpartInstalled))")
                Text("reach=\(boolBadge(coord.debugIsReachable))")
                Spacer()
            }
            .font(.caption.monospacedDigit())
            HStack(spacing: 6) {
                Text("pending context=\(coord.debugPendingContext ? "1" : "0")")
                Text("chatQ=\(coord.debugPendingChatDeltaCount)")
                Spacer()
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func statusDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    private func activationLabel(_ raw: Int) -> String {
        switch raw {
        case 0: return "notActivated"
        case 1: return "inactive"
        case 2: return "activated"
        default: return "\(raw)"
        }
    }

    private func boolBadge(_ b: Bool) -> String { b ? "✓" : "×" }

    // MARK: - Debug State Controls

    private var debugStateBar: some View {
        HStack(spacing: 8) {
            Button {
                BolaDebugLog.shared.log(.command, "[DEBUG] force hungry")
                coord.pushPetCoreState(.hungry)
            } label: {
                Text("Enter Hungry")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.purple.opacity(0.2)))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)

            Button {
                BolaDebugLog.shared.log(.command, "[DEBUG] force thirsty")
                coord.pushPetCoreState(.thirsty)
            } label: {
                Text("Enter Thirsty")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Button {
                BolaDebugLog.shared.log(.command, "[DEBUG] force sleepWait")
                coord.pushPetCoreState(.sleepWait)
            } label: {
                Text("Enter Sleepy")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.indigo.opacity(0.2)))
                    .foregroundStyle(.indigo)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    if selectedCategories.count == BolaDebugLog.Category.allCases.count {
                        selectedCategories.removeAll()
                    } else {
                        selectedCategories = Set(BolaDebugLog.Category.allCases)
                    }
                } label: {
                    Text(selectedCategories.count == BolaDebugLog.Category.allCases.count ? "全不" : "全部")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)

                ForEach(BolaDebugLog.Category.allCases, id: \.self) { cat in
                    let on = selectedCategories.contains(cat)
                    Button {
                        if on { selectedCategories.remove(cat) }
                        else { selectedCategories.insert(cat) }
                    } label: {
                        Text(cat.short)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(on ? categoryColor(cat).opacity(0.25) : Color(.tertiarySystemBackground)))
                            .foregroundStyle(on ? categoryColor(cat) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Log list

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: log.entries.count) { _, _ in
                guard autoScroll, let last = filteredEntries.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var filteredEntries: [BolaDebugLog.Entry] {
        if selectedCategories.count == BolaDebugLog.Category.allCases.count {
            return log.entries
        }
        return log.entries.filter { selectedCategories.contains($0.category) }
    }

    private func entryRow(_ entry: BolaDebugLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(entry.source == .iOS ? "📱" : "⌚️")
                .font(.caption2)
            Text(entry.category.short)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(categoryColor(entry.category))
            Text(entry.message)
                .font(.caption.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button("复制此行") {
                let line = "\(Self.timeFormatter.string(from: entry.timestamp)) [\(entry.category.short)] \(entry.message)"
                UIPasteboard.general.string = line
            }
        }
    }

    private func categoryColor(_ c: BolaDebugLog.Category) -> Color {
        switch c {
        case .petState: return .purple
        case .wc:       return .blue
        case .send:     return .teal
        case .recv:     return .indigo
        case .chat:     return .orange
        case .llm:      return .pink
        case .speech:   return .mint
        case .command:  return .brown
        case .pending:  return .yellow
        case .meal:     return .green
        case .error:    return .red
        case .info:     return .gray
        }
    }
}

#Preview {
    NavigationStack {
        IOSDebugLogSheet()
    }
}
