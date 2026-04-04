//
//  LifeRecordEmojiPaletteView.swift
//  添加生活卡片：横向分区 emoji 调色板 + 可选手动输入。
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
        let emojis: [String]
    }

    /// 分类横向条：每类一条 `ScrollView(.horizontal)`，避免单列过长。
    static let categories: [Category] = [
        Category(id: "common", title: "常用", emojis: commonEmojis),
        Category(id: "smileys", title: "表情", emojis: smileyEmojis),
        Category(id: "food", title: "食物", emojis: foodEmojis),
        Category(id: "travel", title: "旅行", emojis: travelEmojis),
        Category(id: "sport", title: "运动", emojis: sportEmojis),
        Category(id: "symbols", title: "符号", emojis: symbolEmojis)
    ]

    private static let commonEmojis: [String] = [
        "⭐️", "✅", "❤️", "📌", "✨", "🎯", "💡", "📝", "🔥", "🎉", "☀️", "🌙", "📅", "⏰", "🎵", "💬",
        "👍", "👎", "🙏", "💯", "🆗", "🆒", "⚡️", "💤", "🎊", "🎈", "🎁", "🏆", "📎", "🔗", "🔔", "📣"
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

    private static let symbolEmojis: [String] = [
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "💕", "💞", "💓", "💗", "💖", "💘", "💝",
        "☮️", "✝️", "☪️", "🕉️", "☸️", "✡️", "🔯", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️",
        "✨", "🔥", "💧", "🌈", "☀️", "🌙", "⭐️", "🌟", "☁️", "⛈️", "❄️", "☃️", "🎵", "🎶", "🔔", "📌"
    ]
}

struct LifeRecordEmojiPaletteView: View {
    let kind: LifeRecordKind
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                selection = ""
            } label: {
                Text("默认（跟随类型）")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            paletteSection(title: "与类型相关", emojis: LifeRecordIconPick.presets(for: kind))

            ForEach(LifeRecordEmojiPaletteData.categories) { category in
                paletteSection(title: category.title, emojis: category.emojis)
            }

            TextField("输入或粘贴 emoji", text: $selection)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paletteSection(title: String, emojis: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
                        Button {
                            selection = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(minWidth: 40, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == emoji ? BolaTheme.accent.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(selection == emoji ? 0.12 : 0.06), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
