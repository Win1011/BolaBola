//
//  IOSHelpCenterView.swift
//

import SwiftUI

// MARK: - Main View

struct IOSHelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSidebarOpen = true
    @State private var selectedItem: HelpItem? = HelpCenterContent.allSections.first?.items.first

    private let sidebarWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .background(Color(.systemBackground))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSidebarOpen.toggle()
                }
            } label: {
                Image(systemName: isSidebarOpen ? "xmark" : "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)

            Spacer()

            Text("帮助中心")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    // MARK: Content Area

    private var contentArea: some View {
        ZStack(alignment: .leading) {
            articleArea

            if isSidebarOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea(edges: .bottom)
                    .onTapGesture {
                        closeSidebar()
                    }

                HelpCenterSidebarView(
                    selectedItem: $selectedItem,
                    onSelectItem: { closeSidebar() }
                )
                .frame(width: sidebarWidth)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.14), radius: 16, x: 6, y: 0)
                .transition(.move(edge: .leading))
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var articleArea: some View {
        if let item = selectedItem, let article = item.content {
            ScrollView {
                HelpArticleBodyView(article: article)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 48)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 38))
                    .foregroundStyle(.quaternary)
                Text("从左侧目录选择条目阅读")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isSidebarOpen = false
        }
    }
}

// MARK: - Sidebar

private struct HelpCenterSidebarView: View {
    @Binding var selectedItem: HelpItem?
    let onSelectItem: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(HelpCenterContent.allSections) { section in
                    sectionHeader(section.title)
                    ForEach(section.items) { item in
                        if let children = item.children {
                            groupHeader(item.title)
                            ForEach(children) { child in
                                sidebarRow(child, indented: true)
                            }
                        } else {
                            sidebarRow(item, indented: false)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .frame(maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func sidebarRow(_ item: HelpItem, indented: Bool) -> some View {
        let isSelected = selectedItem?.id == item.id
        return Button {
            selectedItem = item
            onSelectItem()
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isSelected ? BolaTheme.accent : .clear)
                    .frame(width: 3)

                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? BolaTheme.accent : Color.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, indented ? 32 : 20)
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? BolaTheme.accent.opacity(0.1) : .clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Article Body

private struct HelpArticleBodyView: View {
    let article: HelpArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .h1(let text):
            Text(text)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

        case .h2(let text):
            Text(text)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
                .padding(.bottom, 10)

        case .body(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

        case .boldLeadBody(let bold, let rest):
            (Text(bold).bold() + Text(rest))
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

        case .divider:
            Divider()
                .padding(.vertical, 16)
        }
    }
}
