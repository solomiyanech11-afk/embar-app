//
//  HomeTagPill.swift
//  Embar
//
//  Пігулка тега (SPEC §5.2) — єдина реалізація для рядка тудушки, рядка
//  вводу і тег-пікера (раніше — 3 копії без truncatedChip: довгий тег
//  розтягував рядок). Колір — слот палітри за іменем (HomeTags.colorIndex).
//

import SwiftUI

struct HomeTagPill: View {
    let label: String
    let palette: Palette
    /// false — сіра пігулка («+ тег» / «Без тегу»)
    var colored: Bool = true
    /// Версія пікера-острівця: 11pt, паддінг 11/4
    var large: Bool = false
    /// Обвід ink 1.5 — вибрана пігулка в пікері
    var activeRing: Bool = false

    var body: some View {
        // colorIndex — від ПОВНОГО імені (обрізання лише візуальне)
        Text(label.truncatedChip())
            .font(.emUI(large ? 11 : 10))
            .foregroundStyle(colored ? EmbarColors.ink2 : EmbarColors.ink3)
            .lineLimit(1)
            .padding(.horizontal, large ? 11 : (colored ? 8 : 9))
            .padding(.vertical, large ? 4 : 2)
            .background(
                Capsule().fill(colored ? palette.sticky[HomeTags.colorIndex(for: label)]
                                       : Color.black.opacity(0.05))
            )
            .overlay(Capsule().stroke(activeRing ? EmbarColors.ink : .clear, lineWidth: 1.5))
    }
}
