//
//  EmbarStepper.swift
//  Embar
//
//  Крихітний степер «− значення +» у світлій капсулі. Один вигляд на всі
//  місця, де значення перебирається по кроках: години й хвилини в календарі
//  (EmbarTimeStepper) і «Нагадати» в редакторі стіка. Вміст посередині дає
//  господар — це може бути і текст, і поле вводу.
//

import SwiftUI

struct EmbarStepper<Label: View>: View {
    /// `inline` — числа в одній світлій капсулі (години й хвилини).
    /// `filled` — значення на чорній пігулці, а − і + окремими кружечками
    /// по краях: так значення читається здалеку і не зливається з кнопками
    enum Style { case inline, filled }

    var style: Style = .inline
    /// Чорнила кольорової поверхні (стік, SPEC §15.57); nil = панельні
    var inks: StickyInk.Tokens? = nil
    var onMinus: () -> Void
    var onPlus: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        switch style {
        case .inline:
            HStack(spacing: 0) {
                button("minus", action: onMinus)
                label()
                button("plus", action: onPlus)
            }
            .padding(2)
            .background(Capsule().fill(inks?.buttonBg ?? Color.black.opacity(0.06)))
        case .filled:
            // Зріст — як у mini-сегмента (дп/пп): відступи 9×3, щоб
            // контроли поруч читались одним набором (фідбек 2026-08-19)
            HStack(spacing: 5) {
                roundButton("minus", action: onMinus)
                label()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(EmbarColors.ink))
                roundButton("plus", action: onPlus)
            }
        }
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph(icon)
                .frame(width: 19, height: 19)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph(icon)
                .frame(width: 19, height: 19)
                .background(Circle().fill(inks?.buttonBg ?? Color.black.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    private func glyph(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(inks?.ink2 ?? EmbarColors.ink2)
    }
}
