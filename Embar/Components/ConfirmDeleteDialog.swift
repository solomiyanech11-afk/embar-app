//
//  ConfirmDeleteDialog.swift
//  Embar
//
//  Маленьке віконце-питання для видалення КОНТЕЙНЕРА (папка рідера/нотаток,
//  стіна стіків): «лише контейнер» чи «разом із вмістом» (фідбек 2026-07-07).
//  Це свідомий виняток із правила «без confirm» (SPEC §8.2): у контейнера
//  два різні сценарії видалення, тост-undo сам вибір не замінить.
//  Після вибору — як завжди, миттєва дія + undo-тост.
//
//  Chrome (скрим, картка, заголовок) — спільний EmbarDialog.
//

import SwiftUI

struct ConfirmDeleteDialog: View {
    /// «Видалити папку «X»?» — назва підставляється як %@ у ключ каталогу
    let title: LocalizedStringKey
    /// «Лише папку - блокноти залишаться»
    let keepLabel: LocalizedStringKey
    /// «Разом із блокнотами»
    let purgeLabel: LocalizedStringKey
    var onKeep: () -> Void
    var onPurge: () -> Void
    var onCancel: () -> Void

    var body: some View {
        // Мова прототипу: пігулки .reader-entry-mode-btn — нейтральна
        // сіра і залита danger-токеном (консистентність, фідбек)
        EmbarDialog(title: title, dismissLabel: "Скасувати", onCancel: onCancel) {
            ConfirmChoicePill(label: keepLabel, fill: .black.opacity(0.06),
                              text: EmbarColors.ink2, action: onKeep)
            ConfirmChoicePill(label: purgeLabel, fill: EmbarColors.danger,
                              text: .white, action: onPurge)
        }
    }
}
