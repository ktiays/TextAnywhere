//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

struct SearchableMenuItem: Identifiable, Hashable {

    let id: String
    let title: String
    var detail: String?
    var searchTerms: [String] = []

    /// Lower ranks are better matches: 0 for an exact match, 1 for a prefix match,
    /// and 2 for a match anywhere in the title or a search term.
    func matchRank(for query: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return ([title] + searchTerms)
            .compactMap { term -> Int? in
                if term.compare(query, options: options) == .orderedSame {
                    return 0
                }
                if term.range(of: query, options: options.union(.anchored)) != nil {
                    return 1
                }
                if term.range(of: query, options: options) != nil {
                    return 2
                }
                return nil
            }
            .min()
    }
}

struct SearchableMenu: View {

    let items: [SearchableMenuItem]
    let selectedID: String?
    let searchPrompt: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var highlightedID: String?
    @State private var scrollTarget: ScrollTarget?
    @State private var lastPointerLocation: NSPoint?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        let filteredItems = self.filteredItems
        VStack(spacing: 0) {
            TextField(searchPrompt, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .padding()
                .onSubmit {
                    selectHighlightedItem()
                }

            Divider()

            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                row(for: item)
                                    .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onAppear {
                        if let highlightedID {
                            proxy.scrollTo(highlightedID, anchor: .center)
                        }
                    }
                    .onChange(of: scrollTarget) {
                        guard let scrollTarget else { return }
                        proxy.scrollTo(scrollTarget.id, anchor: scrollTarget.anchor)
                    }
                }
            }
        }
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onAppear {
            highlightedID = initialHighlightedID
            lastPointerLocation = NSEvent.mouseLocation
            isSearchFieldFocused = true
        }
        .onChange(of: trimmedSearchText) {
            if trimmedSearchText.isEmpty {
                highlightedID = initialHighlightedID
                if let highlightedID {
                    scrollTarget = ScrollTarget(id: highlightedID, anchor: .center)
                }
            } else {
                highlightedID = self.filteredItems.first?.id
                if let highlightedID {
                    scrollTarget = ScrollTarget(id: highlightedID, anchor: .top)
                }
            }
        }
        .fontDesign(.rounded)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var initialHighlightedID: String? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return items.first?.id
    }

    private var filteredItems: [SearchableMenuItem] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in
                item.matchRank(for: query).map { (rank: $0, offset: offset, item: item) }
            }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.item)
    }

    private func row(for item: SearchableMenuItem) -> some View {
        HStack {
            Text(item.title)
                .lineLimit(1)
            Spacer()
            if let detail = item.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .opacity(item.id == selectedID ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if highlightedID == item.id {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            highlightFromPointer(item.id)
        }
        .onTapGesture {
            onSelect(item.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.id == selectedID ? [.isButton, .isSelected] : .isButton)
    }

    /// Hover events also fire when rows scroll under a stationary pointer, for example during
    /// keyboard navigation. Only an actual pointer movement may take over the highlight.
    private func highlightFromPointer(_ id: String) {
        let location = NSEvent.mouseLocation
        guard location != lastPointerLocation else { return }
        lastPointerLocation = location
        highlightedID = id
    }

    private func moveHighlight(by offset: Int) {
        let filteredItems = self.filteredItems
        guard !filteredItems.isEmpty else { return }
        let currentIndex = highlightedID.flatMap { id in
            filteredItems.firstIndex { $0.id == id }
        }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        } else {
            nextIndex = offset > 0 ? 0 : filteredItems.count - 1
        }
        let nextID = filteredItems[nextIndex].id
        highlightedID = nextID
        scrollTarget = ScrollTarget(id: nextID, anchor: nil)
    }

    private func selectHighlightedItem() {
        let filteredItems = self.filteredItems
        guard let item = filteredItems.first(where: { $0.id == highlightedID }) ?? filteredItems.first else {
            return
        }
        onSelect(item.id)
    }
}

private struct ScrollTarget: Equatable {

    let id: String
    let anchor: UnitPoint?
    let token = UUID()
}
