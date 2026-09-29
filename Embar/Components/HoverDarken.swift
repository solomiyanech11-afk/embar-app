//
//  HoverDarken.swift
//  Embar
//
//  Спільний hover-стан кнопок-чіпів (фідбек 2026-08-18: кнопки розгорнутого
//  стіка ніяк не реагували на мишу). Легке затемнення поверх наявного фону —
//  працює і на прозорих кнопках, і на пігулках із заливкою.
//

import SwiftUI

private struct HoverDarkenModifier<S: Shape>: ViewModifier {
    let shape: S
    let strength: Double
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                shape.fill(Color.black.opacity(hovering ? strength : 0))
                    .allowsHitTesting(false)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Затемнює `shape` поверх вʼюхи, поки курсор над нею.
    /// Форма має збігатися з фоном кнопки (Capsule для пігулок, Circle
    /// для круглих)
    func hoverDarken<S: Shape>(_ shape: S, strength: Double = 0.07) -> some View {
        modifier(HoverDarkenModifier(shape: shape, strength: strength))
    }
}
