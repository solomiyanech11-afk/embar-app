//
//  CascadeReveal.swift
//  Embar
//
//  Каскадна поява (SPEC §7.2-A, виняток): fade + підйом 8pt із стаггером
//  за порядком. Керується onAppear, а не .transition — бо transition при
//  swap через .id всередині ScrollView НЕ спрацьовує (перевірено), а
//  onAppear при зміні identity піддерева — завжди.
//

import SwiftUI

/// Направлений «в'їзд сторінки-картки» (фліп тек) для вмісту всередині
/// ScrollView: .transition при .id-swap там не спрацьовує (перевірено),
/// тож новий вміст в'їжджає onAppear-ом — слайд 36pt з фейдом у бік навігації
struct SlideInPage<Content: View>: View {
    let direction: Int
    @ViewBuilder let content: Content

    @State private var shown = false

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : CGFloat(direction >= 0 ? 36 : -36))
            .onAppear {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.28)) {
                    shown = true
                }
            }
    }
}

/// Хто в поточній вибірці каскад уже відіграв (ревʼю 2026-08-18, знахідка 5).
///
/// Саме вікно `cascadeArmed` (~0.7 с після перемикання стіни) захищає лише
/// від повторів ПІСЛЯ себе. Усередині нього pin/done пересортовує стіну,
/// картка перескакує в іншу колонку — а в лінивій масонрі це СТРУКТУРНЕ
/// перестворення вьюхи, тож її `@State shown` починається з нуля і хвиля
/// грає вдруге: незаймані сусіди видимо блимають.
///
/// Реєстр памʼятає id, які вже показались, і другого разу каскад не дає.
/// Референс-тип навмисно: живе у @State як контейнер, мутація SwiftUI не
/// інвалідовує (це памʼять, а не стан).
final class CascadeLedger {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    private var revealed = Set<UUID>()

    /// Нова вибірка — каскад грає всім наново
    func reset() { revealed.removeAll() }

    func hasRevealed(_ id: UUID) -> Bool { revealed.contains(id) }

    func mark(_ id: UUID) { revealed.insert(id) }
}

struct CascadeReveal<Content: View>: View {
    let order: Int
    /// false — показати миттєво (перф-фікс 2026-08-16: у лінивій стіні
    /// onAppear приходить і при скролі, і хвиля програвалась би щоразу,
    /// коли картка повертається у вʼюпорт; каскад лишаємо тільки на
    /// свіжій пере-вибірці стіни)
    var animated: Bool = true
    @ViewBuilder let content: Content

    @State private var shown = false

    var body: some View {
        content
            .opacity(shown || !animated ? 1 : 0)
            .offset(y: shown || !animated ? 0 : 8)
            .onAppear {
                guard animated, !shown else { shown = true; return }
                // Стаггер 35мс, обмежений так, щоб хвиля була ≤350мс
                withAnimation(.easeOut(duration: 0.2)
                    .delay(min(Double(order) * 0.035, 0.15))) {
                    shown = true
                }
            }
    }
}
