//
//  HomeTodoRow.swift
//  Embar
//
//  Рядок тудушки (SPEC §5.2): HomeRowShell (чекбокс, інлайн-edit,
//  hover-delete) + тег-пігулка/+тег у правому слоті.
//  Тег-пікер — popover (Без тегу / кастомні / новий).
//

import SwiftUI

struct TodoRow: View {
    let todo: Todo
    let isEditing: Bool
    let palette: Palette
    let customTags: [HomeTag]

    var onToggle: () -> Void
    var onStartEdit: () -> Void
    var onCommitEdit: (String) -> Void
    var onCancelEdit: () -> Void
    var onOpenTagPicker: () -> Void
    var onDelete: () -> Void
    @Binding var tagPickerBinding: Bool
    var onSelectTag: (String?) -> Void
    var onCreateTag: (String) -> Void

    var body: some View {
        HomeRowShell(
            text: todo.text,
            checked: todo.done,
            struckThrough: todo.done,
            isEditing: isEditing,
            onToggle: onToggle,
            onStartEdit: onStartEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete
        ) { hovering in
            tagArea(hovering)
        }
    }

    @ViewBuilder private func tagArea(_ hovering: Bool) -> some View {
        if let tag = todo.tagName {
            tagPill(tag).popover(isPresented: $tagPickerBinding, arrowEdge: .bottom) { picker }
        } else if hovering || tagPickerBinding {
            // Тримаємо кнопку-якір, поки пікер відкритий — інакше при переході
            // миші на попап рядок втрачає hover, кнопка зникає і попап закривається
            Button(action: onOpenTagPicker) {
                HomeTagPill(label: String(localized: "+ тег", comment: "Кнопка додати тег до тудушки"), palette: palette, colored: false)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $tagPickerBinding, arrowEdge: .bottom) { picker }
        }
    }

    private func tagPill(_ tag: String) -> some View {
        Button(action: onOpenTagPicker) {
            HomeTagPill(label: tag, palette: palette)
        }
        .buttonStyle(.plain)
    }

    private var picker: some View {
        HomeTagPicker(
            selected: todo.tagName,
            customTags: customTags,
            palette: palette,
            onSelect: onSelectTag,
            onCreate: onCreateTag
        )
    }
}

// MARK: - Тег-пікер (popover)

struct HomeTagPicker: View {
    let selected: String?
    let customTags: [HomeTag]
    let palette: Palette
    var onSelect: (String?) -> Void
    var onCreate: (String) -> Void

    @State private var creating = false
    @State private var newName = ""

    /// Лише створені користувачем теги (жодних дефолтних)
    private var allTags: [String] { customTags.map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow(spacing: 5) {
                pill(String(localized: "Без тегу", comment: "Опція у виборі тега — без тега"), isNoTag: true, active: selected == nil) { onSelect(nil) }
                ForEach(allTags, id: \.self) { tag in
                    pill(tag, isNoTag: false, active: selected == tag) { onSelect(tag) }
                }
            }
            Divider().overlay(EmbarColors.line)
            if creating {
                TextField("Назва тега", text: $newName)
                    .textFieldStyle(.plain).font(.emUI(12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.04)))
                    .onSubmit { if !newName.isEmpty { onCreate(newName) } }
            } else {
                Button { creating = true } label: {
                    Text("＋ створити новий")
                        .font(.emDisplay(12, italic: true)).foregroundStyle(EmbarColors.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 200)
    }

    private func pill(_ label: String, isNoTag: Bool, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HomeTagPill(label: label, palette: palette,
                        colored: !isNoTag, large: true, activeRing: active)
        }
        .buttonStyle(.plain)
    }
}
