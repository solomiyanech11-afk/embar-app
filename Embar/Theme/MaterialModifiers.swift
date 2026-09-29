//
//  MaterialModifiers.swift
//  Embar
//
//  View-модифікатори матеріальності (DESIGN-DIRECTIONS §1): читають
//  токени з Environment(\.embarMaterial) і замінюють ~25 ручних заливок
//  на один виклик кожна. Opaque-гілка = сьогоднішній вигляд байт-у-байт.
//

import SwiftUI

// MARK: - L0: корінь панелі («молочна» плівка)

private struct PanelBacking: ViewModifier {
    @Environment(\.embarMaterial) private var material
    /// Тригер перерендеру: вибір «фон панелі» (Settings) міняє
    /// EmbarColors.surface, а modifier лише з @Environment SwiftUI вважає
    /// незмінним і фон не перефарбовувався (фідбек 2026-07-19)
    @AppStorage("panelSurface") private var surfaceRaw = PanelSurface.warm.rawValue

    func body(content: Content) -> some View {
        content.background(fill)
    }

    private var fill: Color {
        switch material.theme {
        case .opaque:     EmbarColors.surface          // байт-у-байт
        case .glass:      EmbarColors.surface.opacity(material.panelBackingOpacity)
        case .levitation: Color.clear                  // острови над столом
        }
    }
}

extension View {
    /// L0-корінь панелі й повнопанельні НЕ-оверлейні фони.
    /// Opaque → EmbarColors.surface; Glass → молоко з прозорістю;
    /// Левітація → прозоро (елементи стають островами)
    func embarPanelBacking() -> some View {
        modifier(PanelBacking())
    }
}

// MARK: - L0-оверлеї (редактор, блокнот, шторка, sheet)

private struct OverlaySurface: ViewModifier {
    @Environment(\.embarMaterial) private var material
    /// Той самий тригер, що в PanelBacking — оверлеї теж фарбуються surface
    @AppStorage("panelSurface") private var surfaceRaw = PanelSurface.warm.rawValue

    func body(content: Content) -> some View {
        if material.theme == .opaque {
            content.background(EmbarColors.surface) // байт-у-байт
        } else {
            // Матеріал розмиває контент ПІД оверлеєм (стіну), тінт додає
            // молока для читабельності — оверлей лишається склом без «привидів»
            content
                .background(EmbarColors.surface.opacity(material.overlayTintOpacity))
                .background(.regularMaterial)
        }
    }
}

extension View {
    /// Повнопанельні оверлеї, що сидять НАД контентом панелі (не над
    /// столом): матеріал + молочний тінт замість опакного surface
    func embarOverlaySurface() -> some View {
        modifier(OverlaySurface())
    }
}

// MARK: - L1: острови (картки, стіки, sheet-картки)

private struct Island: ViewModifier {
    @Environment(\.embarMaterial) private var material
    let fill: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if material.theme == .opaque {
            content.background(fill).clipShape(shape) // байт-у-байт
        } else {
            content
                // Пастель@0.4 поверх .thinMaterial: над світлим склом
                // може стати лише СВІТЛІШОЮ → чорнильний текст читається
                .background(fill.opacity(material.islandAlpha))
                .background(.thinMaterial)
                .clipShape(shape)
                .shadow(color: .black.opacity(material.islandShadow?.opacity ?? 0),
                        radius: material.islandShadow?.radius ?? 0,
                        y: material.islandShadow?.y ?? 0)
        }
    }
}

extension View {
    /// L1-острів (картка/стік): opaque → fill; glass/левітація →
    /// fill.opacity(0.4) поверх .thinMaterial (+тінь острова в Левітації).
    /// Замінює пару `.background(fill).clipShape(RoundedRectangle(...))`.
    func embarIsland(_ fill: Color, cornerRadius: CGFloat) -> some View {
        modifier(Island(fill: fill, cornerRadius: cornerRadius))
    }

    /// Матеріальна заливка для shape-based фонів (NoteCard/MentionPopup,
    /// де фон — не проста `.background(color)`, а власна фігура-ZStack).
    /// В opaque — прозоро (нічого не малює: викликач лишає свій fill).
    @ViewBuilder func embarIslandUnderlay(cornerRadius: CGFloat) -> some View {
        EmbarIslandUnderlay(cornerRadius: cornerRadius)
    }
}

/// .thinMaterial-підкладка під shape-fill острова; в opaque — Color.clear
private struct EmbarIslandUnderlay: View {
    @Environment(\.embarMaterial) private var material
    let cornerRadius: CGFloat

    var body: some View {
        if material.theme == .opaque {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).fill(.thinMaterial)
        }
    }
}
