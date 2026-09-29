//
//  QuickComposer.swift
//  Embar
//
//  Спільний рядок швидкого вводу (прототип .quick-input): Стіки й Нотатки
//  мали два ідентичні дублі по 28 рядків — правка розміру/радіуса летіла б
//  лише в один таб (code review, reuse).
//

import SwiftUI
import AppKit

struct QuickComposer: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    /// Показ панелі → фокус сюди (кореневий фікс 2026-07-07: «нуль тертя»).
    /// false — коли поверхня накрита оверлеєм (редактор/шторка/розгорнутий стік)
    var autoFocus: Bool = true
    var onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        // Ліквід глас (дизайн-хендоф 2026-07-19, варіант 1b): біле скло
        // 38% + blur, білий контур, стіки проступають крізь поле розмито.
        // Масштаб адаптовано з 390px-макета під нашу панель
        ZStack(alignment: .trailing) {
            TextField("", text: $text,
                      prompt: Text(placeholder)
                        // Єдиний тон плейсхолдерів (консистентність 2026-07-22)
                        .foregroundStyle(EmbarColors.placeholder))
                .textFieldStyle(.plain)
                .font(.emUI(14))
                .foregroundStyle(EmbarColors.ink)
                .padding(.leading, 18)
                .padding(.trailing, 46)
                .padding(.vertical, 11)
                .frame(minHeight: 46)
                // Без системного focus-ефекту: рінг при кліку читався як
                // «сильніша тінь» (фідбек 2026-07-20)
                .focusEffectDisabled()
                .focused($focused)
                .onSubmit(onSubmit)
                .onReceive(NotificationCenter.default.publisher(
                    for: .embarPanelDidShow)) { _ in
                    if autoFocus { focused = true }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: .embarPanelDidHide)) { _ in
                    focused = false
                }

            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(Circle().fill(EmbarColors.ink))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 9)
        }
        .modifier(ComposerRowChrome())
    }
}

/// Спільна «оболонка» рядка під табами (скло + кільце тіні + відступи).
/// Винесена з QuickComposer (P2.34): нею користується і рядок-кнопка
/// «+ Новий блокнот» у Рідері - однакова висота й геометрія гарантовані
/// одним кодом, а не копією
struct ComposerRowChrome: ViewModifier {
    /// Тінь параметрами: композери носять повну (дефолти = історичні
    /// значення), рядок «+ Новий блокнот» - мʼякшу (фідбек 2026-09-04:
    /// кнопка виглядала надто «піднятою»)
    var shadowOpacity: Double = 0.20
    var shadowRadius: CGFloat = 11
    var shadowOffsetY: CGFloat = 4

    func body(content: Content) -> some View {
        content
            // Скло — спільний компонент (Components/ComposerGlass.swift):
            // рідер використовує той самий, вигляд ідентичний
            .background(ComposerGlassBackdrop(cornerRadius: 12))
            // Тінь — ОКРЕМА розмита фігура ЗА склом, не .shadow: той малює
            // тінь від власних пікселів в'юхи, а скляний backdrop майже
            // прозорий, поки вікно не стане key — тінь з'являлась лише після
            // першого кліку (фідбек 2026-07-19). Нутро фігури ВИРІЗАНО маскою:
            // інакше скло семплило темне під собою і насиченість тіні
            // «стрибала» між неактивним/key станами вікна (фідбек ×2) —
            // лишається тільки зовнішнє кільце, однакове завжди
            .background(
                // Виразніша за колишні 0.15 (фідбек 2026-07-20: «навпаки
                // збільшити»)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(shadowOpacity))
                    .blur(radius: shadowRadius)
                    .offset(y: shadowOffsetY)
                    .mask {
                        ZStack {
                            Rectangle().padding(-30)
                            RoundedRectangle(cornerRadius: 12)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .allowsHitTesting(false)
            )
            .padding(.horizontal, 16)
            .padding(.top, 15)   // повітря між табами і полем (фідбек 2026-07-20)
            .padding(.bottom, 6)
    }
}
