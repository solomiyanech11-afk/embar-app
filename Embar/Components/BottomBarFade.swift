//
//  BottomBarFade.swift
//  Embar
//
//  Спільний фейд-подіум нижніх барів (бар стін у Стіках, бари папок у
//  Нотатках і Рідері): прозорий флоут, контент скролить під бар і
//  розчиняється в димці кольору панелі (прототип: .reader-folder-bar
//  background:transparent + .panel-footer::before). Порожні зони
//  пропускають кліки — ловить лише сам чіп.
//
//  Коли тижневої смужки внизу нема («Показувати тиждень» вимкнено;
//  Home сховано з v1 — H2), бар піднімається на 10pt від краю панелі,
//  а димка стає вищою і щільнішою: інакше чіпи висіли б на самому
//  зрізі, а картки просвічували б під ними до краю.
//

import SwiftUI

struct BottomBarFade: ViewModifier {
    @AppStorage("showWeekStrip") private var showWeekStrip = true

    func body(content: Content) -> some View {
        content
            .padding(.bottom, showWeekStrip ? 6 : 16)
            .background(
                LinearGradient(
                    colors: [EmbarColors.surface.opacity(0),
                             EmbarColors.surface.opacity(showWeekStrip ? 0.92 : 0.98)],
                    startPoint: .top, endPoint: .bottom
                )
                // Без смужки димка починається вище за бар — довший розгін
                .padding(.top, showWeekStrip ? 0 : -24)
                .allowsHitTesting(false)
            )
    }
}

extension View {
    /// Нижній бар чіпів: відступ від краю панелі + димка-фейд під ним
    func bottomBarFade() -> some View { modifier(BottomBarFade()) }
}
