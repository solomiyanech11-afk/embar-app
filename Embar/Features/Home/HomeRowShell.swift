//
//  HomeRowShell.swift
//  Embar
//
//  Спільна анатомія рядка списків Home (SPEC §5.2): чекбокс, текст з
//  інлайн-редагуванням, hover-фон і смітник. Тудушки і звички відрізняються
//  лише правим слотом (тег-пігулка / стрік 🔥) — він передається як
//  @ViewBuilder із поточним hover-станом.
//

import SwiftUI

struct HomeRowShell<Trailing: View>: View {
    let text: String
    let checked: Bool
    /// Виконана тудушка: ink3 + перекреслення (звички лишаються ink)
    var struckThrough: Bool = false
    let isEditing: Bool

    var onToggle: () -> Void
    var onStartEdit: () -> Void
    /// Коміт з ВЛАСНИМ буфером рядка (не спільним @State батька):
    /// спільний буфер перезаписував рядок A текстом B при перемиканні
    /// редагування кліком (code review 2026-07-04)
    var onCommitEdit: (String) -> Void
    var onCancelEdit: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var trailing: (_ hovering: Bool) -> Trailing

    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var editFocus: Bool

    var body: some View {
        HStack(spacing: 11) {
            HomeCheckbox(checked: checked, action: onToggle)
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain).font(.emUI(13)).foregroundStyle(EmbarColors.ink)
                    .focused($editFocus)
                    .onAppear { draft = text; editFocus = true } // сід + авто-фокус
                    .onSubmit { onCommitEdit(draft) }
                    .onExitCommand(perform: onCancelEdit) // Esc = скасувати, не зберегти
                    .onChange(of: editFocus) { _, focused in
                        if !focused { onCommitEdit(draft) } // блюр = зберегти СВІЙ драфт
                    }
            } else {
                Text(text)
                    .font(.emUI(13))
                    .foregroundStyle(struckThrough ? EmbarColors.ink3 : EmbarColors.ink)
                    .strikethrough(struckThrough)
                    .lineLimit(1)
                    .onTapGesture(perform: onStartEdit)
            }
            Spacer(minLength: 6)
            trailing(hovering)
            if hovering && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(EmbarColors.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.black.opacity(0.025) : .clear))
        .onHover { hovering = $0 }
    }
}
