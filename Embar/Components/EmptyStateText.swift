//
//  EmptyStateText.swift
//  Embar
//
//  Брендовий двохрядковий порожній стан (SPEC §8.1.1): Fraunces italic 15 +
//  Inter 12, приглушений. Був продубльований тричі (ContentView, Стіки,
//  Нотатки) з дрейфом розміщення. Позиціювання — на боці викликача.
//

import SwiftUI

struct EmptyStateText: View {
    // LocalizedStringKey, а не String: інакше текст, переданий згори,
    // не проходить через каталог перекладів (i18n 2026-08-03)
    let line1: LocalizedStringKey
    var line2: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(line1).font(.emDisplay(15, italic: true))
            if let line2 { Text(line2).font(.emUI(12)) }
        }
        .foregroundStyle(EmbarColors.ink3)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
