//
//  LifeRecordEmojiPaletteView.swift
//  添加生活卡片：紧凑图标入口 + 类输入法 picker。
//

import SwiftUI

enum LifeRecordIconPick {
    static func presets(for kind: LifeRecordKind) -> [String] {
        let common = ["⭐️", "✅", "❤️", "📌", "✨", "🎯", "💡", "📝", "🔥", "🎉", "☀️", "🌙"]
        switch kind {
        case .event, .habitTodo:
            return common + ["📅", "⏰", "🎵", "💬"]
        case .food:
            return common + ["🍜", "🍱", "🥗", "☕️", "🍰", "🥤", "🍳"]
        case .travel:
            return common + ["✈️", "🚗", "🚇", "🧳", "🗺️", "🚲"]
        case .fitness:
            return common + ["🏃", "💪", "🚴", "🏋️", "🧘", "⚽️"]
        case .movie:
            return common + ["🎬", "🍿", "📺", "🎭", "🎧"]
        case .shopping:
            return common + ["🛍️", "🛒", "💳", "🎁", "👜"]
        case .weather:
            return common
        }
    }
}

private enum LifeRecordEmojiPaletteData {
    struct Category: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let emojis: [String]
    }

    static let categories: [Category] = [
        Category(id: "common", title: "常用", symbol: "🕘", emojis: commonEmojis),
        Category(id: "smileys", title: "表情", symbol: "😀", emojis: smileyEmojis),
        Category(id: "food", title: "食物", symbol: "🍜", emojis: foodEmojis),
        Category(id: "nature", title: "自然", symbol: "🌿", emojis: natureEmojis),
        Category(id: "travel", title: "出行", symbol: "✈️", emojis: travelEmojis),
        Category(id: "sport", title: "运动", symbol: "⚽️", emojis: sportEmojis),
        Category(id: "objects", title: "物件", symbol: "🧸", emojis: objectEmojis),
        Category(id: "animals", title: "动物", symbol: "🐶", emojis: animalEmojis),
        Category(id: "symbols", title: "符号", symbol: "❤️", emojis: symbolEmojis)
    ]

    private static let commonEmojis: [String] = [
        "⭐️", "✅", "❤️", "📌", "✨", "🎯", "💡", "📝", "🔥", "🎉", "☀️", "🌙", "📅", "⏰", "🎵", "💬",
        "👍", "👎", "🙏", "💯", "🆗", "🆒", "⚡️", "💤", "🎊", "🎈", "🎁", "🏆", "📎", "🔗", "🔔", "📣",
        "📷", "🎨", "📚", "🧠", "🌸", "🍀", "🕯️", "🫶"
    ]

    private static let smileyEmojis: [String] = [
        "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘",
        "😋", "🤪", "😜", "🤑", "🤗", "🤔", "🤐", "😐", "😑", "😏", "😒", "🙄", "😬", "🥺", "😢", "😭",
        "😤", "😡", "🤬", "🥳", "😎", "🤓", "🧐", "😕", "😮", "😱", "😴", "🤒", "🤕", "🥵", "🥶", "🤯"
    ]

    private static let foodEmojis: [String] = [
        "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅",
        "🥑", "🥦", "🥬", "🌶️", "🌽", "🥕", "🥔", "🍠", "🥐", "🍞", "🥖", "🧀", "🍳", "🥞", "🥓", "🍔",
        "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🥗", "🍝", "🍜", "🍲", "🍣", "🍱", "🥟", "🍤", "🍙", "🍚",
        "🍨", "🍦", "🧁", "🍰", "🎂", "🍫", "🍿", "🍩", "🍪", "☕️", "🍵", "🧋", "🥤", "🍺", "🍻", "🥂"
    ]

    private static let natureEmojis: [String] = [
        "☀️", "🌤️", "⛅️", "🌥️", "☁️", "🌦️", "🌧️", "⛈️", "🌩️", "❄️", "☃️", "🌈", "🌊", "💧", "🔥", "🌪️",
        "🌱", "🌿", "🍀", "🌷", "🌸", "🌹", "🌺", "🌻", "🪻", "🌼", "🌵", "🌲", "🌳", "🪵", "🍄", "🪨",
        "🌙", "⭐️", "🌟", "✨", "🌍", "🪐", "🌌", "🏔️", "⛰️", "🏕️", "🏖️", "🏝️", "🌋", "🫧", "🍃", "🦋"
    ]

    private static let travelEmojis: [String] = [
        "✈️", "🛫", "🛬", "🚁", "🚀", "🚂", "🚄", "🚅", "🚇", "🚊", "🚌", "🚕", "🚗", "🚙", "🛻", "🚚",
        "🏎️", "🏍️", "🛵", "🚲", "🛴", "⛵️", "🛥️", "🛳️", "⚓️", "🗺️", "🧭", "🧳", "🏖️", "🏝️", "🏔️", "⛺️",
        "🏠", "🏨", "🏛️", "🗽", "🗼", "🏰", "🎡", "🎢", "🎠", "🌋", "🗻", "🏕️", "🛤️", "🛣️", "🚧", "🚦"
    ]

    private static let sportEmojis: [String] = [
        "⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🥏", "🎱", "🏓", "🏸", "🏒", "⛳️", "🥊", "🥋", "🎽",
        "🛹", "🛷", "⛸️", "🥌", "🎿", "⛷️", "🏂", "🏋️", "🤸", "🤺", "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊",
        "🚣", "🧗", "🚵", "🚴", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🎗️", "🤿", "🎣", "🪁", "🏹", "⛹️"
    ]

    private static let objectEmojis: [String] = [
        "📱", "⌚️", "💻", "⌨️", "🖥️", "🖨️", "🎧", "📷", "📹", "🎥", "📸", "📺", "📻", "🎮", "🕹️", "🧸",
        "💡", "🕯️", "🔋", "🔦", "🛏️", "🛋️", "🚿", "🧴", "🪥", "🧼", "🧽", "🧺", "🧹", "🪴", "🧳", "🎒",
        "📚", "📔", "📝", "✏️", "🖍️", "📌", "📎", "📦", "🎁", "🔔", "🧠", "🪄", "🔮", "🧩", "🧶", "🪡"
    ]

    private static let animalEmojis: [String] = [
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐤",
        "🐣", "🐥", "🦆", "🦅", "🦉", "🦋", "🐛", "🐝", "🐞", "🐢", "🐠", "🐟", "🐬", "🦭", "🐳", "🦀",
        "🐙", "🦑", "🦐", "🦞", "🐎", "🦄", "🐘", "🦒", "🦌", "🐑", "🐓", "🦜", "🐕‍🦺", "🐈", "🦮", "🐇"
    ]

    private static let symbolEmojis: [String] = [
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "💕", "💞", "💓", "💗", "💖", "💘", "💝",
        "☮️", "✝️", "☪️", "🕉️", "☸️", "✡️", "🔯", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️",
        "✨", "🔥", "💧", "🌈", "☀️", "🌙", "⭐️", "🌟", "☁️", "⛈️", "❄️", "☃️", "🎵", "🎶", "🔔", "📌"
    ]
}

struct LifeRecordEmojiPaletteView: View {
    let kind: LifeRecordKind
    @Binding var selection: String

    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BolaTheme.surfaceBubble)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        Text(displayEmoji)
                            .font(.system(size: 24))
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("选择图标")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(selection.isEmpty ? "当前使用类型默认图标" : "当前已自定义图标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if !selection.isEmpty {
                Button("恢复默认图标") {
                    selection = ""
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(BolaTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showPicker) {
            LifeRecordEmojiPickerSheet(kind: kind, selection: $selection)
        }
    }
    
    private var displayEmoji: String {
        if selection.isEmpty {
            LifeRecordIconPick.presets(for: kind).first ?? "⭐️"
        } else {
            selection
        }
    }
}

private struct LifeRecordEmojiPickerSheet: View {
    let kind: LifeRecordKind
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var activeCategoryID = "contextual"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private var contextualCategory: LifeRecordEmojiPaletteData.Category {
        .init(
            id: "contextual",
            title: "推荐",
            symbol: "✨",
            emojis: LifeRecordIconPick.presets(for: kind)
        )
    }

    private var allCategories: [LifeRecordEmojiPaletteData.Category] {
        [contextualCategory] + LifeRecordEmojiPaletteData.categories
    }

    private var activeCategory: LifeRecordEmojiPaletteData.Category {
        allCategories.first(where: { $0.id == activeCategoryID }) ?? contextualCategory
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    BolaTheme.accent.opacity(0.18),
                                    BolaTheme.accent.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)
                        .overlay {
                            Text(previewEmoji)
                                .font(.system(size: 34))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.isEmpty ? "默认图标" : "当前选择")
                            .font(.headline)
                        Text(selection.isEmpty ? "不单独指定时，随卡片类型显示" : "点任一图标即可替换")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allCategories) { category in
                            Button {
                                activeCategoryID = category.id
                            } label: {
                                HStack(spacing: 6) {
                                    Text(category.symbol)
                                    Text(category.title)
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(activeCategoryID == category.id ? BolaTheme.accent.opacity(0.16) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(activeCategoryID == category.id ? 0.1 : 0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(activeCategory.emojis.enumerated()), id: \.offset) { _, emoji in
                            Button {
                                selection = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selection == emoji ? BolaTheme.accent.opacity(0.2) : Color.white.opacity(0.7))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(selection == emoji ? 0.14 : 0.06), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.97, blue: 0.95),
                        Color(red: 0.95, green: 0.97, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var previewEmoji: String {
        if selection.isEmpty {
            contextualCategory.emojis.first ?? "⭐️"
        } else {
            selection
        }
    }
}
