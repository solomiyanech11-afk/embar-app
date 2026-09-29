//
//  ValueMenu.swift
//  Embar
//
//  Компактний вибір значення: поточне значення з шевроном, спадне меню
//  з варіантами. Один вигляд на всі поверхні — лист налаштувань стіків і
//  редактор стіка (правило «однаковий контрол виглядає однаково»).
//

import SwiftUI

struct ValueMenu<Content: View>: View {
    let label: String
    @ViewBuilder let menu: Content

    var body: some View {
        Menu {
            menu
        } label: {
            HStack(spacing: 3) {
                Text(label).font(.emUI(12, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .foregroundStyle(EmbarColors.ink2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
