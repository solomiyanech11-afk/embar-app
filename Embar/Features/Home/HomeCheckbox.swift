//
//  HomeCheckbox.swift
//  Embar
//
//  Чекбокс-коло 17pt рядків Home (SPEC §5.2) — єдина реалізація для
//  тудушок, звичок і рядків вводу (раніше малювався в 4 місцях).
//

import SwiftUI

struct HomeCheckbox: View {
    var checked: Bool = false
    /// nil — декоративний placeholder у рядку вводу (без кнопки і паддінгу,
    /// щоб не зсувати поле відносно «+»-рядка)
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                circle
                    .padding(3)
                    // ❗ Без contentShape порожнє коло (stroke) ловило кліки
                    // лише по самій лінії 1.5pt — галочку було майже
                    // неможливо поставити
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            circle
        }
    }

    private var circle: some View {
        ZStack {
            Circle().fill(checked ? EmbarColors.ink : .clear)
            Circle().stroke(checked ? EmbarColors.ink : EmbarColors.ink3, lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 17, height: 17)
    }
}
