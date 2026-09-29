//
//  EmbarMotion.swift
//  Embar
//
//  Спільний рух карток у списках (SPEC §7.2-A, ревізія 2026-08-21):
//  «виконано», «закріпити», створення, видалення та їх undo — це рух
//  реальної поверхні, тож картка їде видимим шляхом, а не телепортується.
//  Крива за мошн-принципами проєкту: швидкий старт, сильне сповільнення
//  в кінці, без пружин і желе.
//

import SwiftUI

enum EmbarMotion {
    /// Переїзд/поява/зникнення картки у списку чи на стіні.
    /// 0.5с (було 0.32): з'їзд сусідів після виконаного/видаленого
    /// читався зарізко (фідбек 2026-08-22)
    static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)

    /// Обгортка перестановки: з Reduce Motion — миттєво, без руху (§7.2-A)
    static func reorder(reduceMotion: Bool, _ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(settle, change)
        }
    }
}

/// Проявлення картки на новому місці ПІСЛЯ миттєвої перескладки (пін
/// стіка, фідбек 2026-08-22): анімований переїзд у масонрі тягнув за
/// собою каскадне перетасування колонок — стіна читалась як
/// «перезавантаження». Тому стіна перескладається миттєво, а сама
/// картка тихо проявляється там, де сіла.
///
/// Працює і коли вьюху пересотворено (onAppear свіжого стану), і коли
/// вона пережила перескладку в своїй колонці (onChange прапорця).
struct ArrivalReveal<Content: View>: View {
    /// Ця картка щойно прибула — стартувати з невидимої і проявити
    let active: Bool
    @ViewBuilder let content: Content

    @State private var shown = false

    var body: some View {
        content
            .opacity(active && !shown ? 0 : 1)
            .onAppear(perform: reveal)
            .onChange(of: active) { _, isActive in
                if isActive { reveal() } else { shown = false }
            }
    }

    private func reveal() {
        guard active, !shown else { return }
        withAnimation(.easeOut(duration: 0.35).delay(0.05)) { shown = true }
    }
}
