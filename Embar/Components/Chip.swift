//
//  Chip.swift
//  Embar
//
//  Сірий чіп-пігулка (`.sheet-chip` у прототипі) — для фільтрів у sheets.
//  Для плаваючих folder-барів є білий FolderChip.
//

import SwiftUI

struct Chip: View {
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.emUI(12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.white : EmbarColors.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isActive ? EmbarColors.ink : Color.black.opacity(0.06))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
