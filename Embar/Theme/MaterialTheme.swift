//
//  MaterialTheme.swift
//  Embar
//
//  Вимір МАТЕРІАЛЬНОСТІ панелі поверх системи палітр (DESIGN-DIRECTIONS §1,
//  SPEC §15.17; витягнуто вперед із M6). Одна реалізація з регульованою
//  прозорістю «молока» панелі: Opaque (сьогоднішній вигляд, дефолт) ·
//  Glass (~60% молока + blur столу, острови пастеллю ~40%) · Левітація
//  (0% — елементи-острівці, док-капсула). Палітра й тема незалежні.
//  Reduce Transparency примусово дає Opaque.
//
//  ❗ Opaque-гілка КОЖНОГО токена повертає сьогоднішні літерали —
//  байт-у-байт (закріплено MaterialTokensTests).
//

import SwiftUI

enum MaterialTheme: String, CaseIterable {
    case opaque
    case glass
    case levitation
}

/// Зведені токени матеріальності — чиста величина, рахується один раз
/// у ContentView і їде деревом через Environment(\.embarMaterial)
struct MaterialTokens: Equatable {
    /// Ефективна тема (після Reduce Transparency)
    let theme: MaterialTheme
    /// Прозорість молочної плівки L0: 1.0 / слайдер / 0
    let panelBackingOpacity: Double
    /// Прозорість заливки островів L1: 1.0 / 0.4 / 0.4
    let islandAlpha: Double
    /// Стеля фейд-градієнтів барів: 0.92 / 0.92×молоко / 0
    let fadeMaxOpacity: Double
    /// Чи потрібен AppKit-blur за панеллю (лише Glass)
    let wantsBlurBacking: Bool
    /// Тінь острова (лише Левітація — острови несуть тінь самі)
    let islandShadow: IslandShadow?

    struct IslandShadow: Equatable {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat

        /// Між hover-тінню стіка і тінню bottom-sheet
        static let levitation = IslandShadow(opacity: 0.16, radius: 14, y: 5)
    }

    /// Непрозорість тінту повнопанельних ОВЕРЛЕЇВ (редактор, блокнот,
    /// шторка, sheet): опакно 1.0; у склі/левітації тримаємо стелю 0.35,
    /// щоб контент під оверлеєм (стіна стіків) не «просвічував»
    var overlayTintOpacity: Double {
        theme == .opaque ? 1.0 : max(panelBackingOpacity, 0.35)
    }

    /// Єдине місце правди. reduceTransparency перемагає будь-який вибір.
    static func resolve(theme: MaterialTheme, glassOpacity: Double,
                        reduceTransparency: Bool) -> MaterialTokens {
        let effective = reduceTransparency ? .opaque : theme
        let clampedGlass = min(max(glassOpacity, 0), 1)
        switch effective {
        case .opaque:
            return MaterialTokens(theme: .opaque,
                                  panelBackingOpacity: 1.0,
                                  islandAlpha: 1.0,
                                  fadeMaxOpacity: 0.92,
                                  wantsBlurBacking: false,
                                  islandShadow: nil)
        case .glass:
            return MaterialTokens(theme: .glass,
                                  panelBackingOpacity: clampedGlass,
                                  islandAlpha: 0.4,
                                  fadeMaxOpacity: 0.92 * clampedGlass,
                                  wantsBlurBacking: true,
                                  islandShadow: nil)
        case .levitation:
            return MaterialTokens(theme: .levitation,
                                  panelBackingOpacity: 0,
                                  islandAlpha: 0.4,
                                  fadeMaxOpacity: 0,
                                  wantsBlurBacking: false,
                                  islandShadow: .levitation)
        }
    }
}

// MARK: - Environment

private struct EmbarMaterialKey: EnvironmentKey {
    static let defaultValue = MaterialTokens.resolve(
        theme: .opaque, glassOpacity: 0.6, reduceTransparency: false)
}

extension EnvironmentValues {
    var embarMaterial: MaterialTokens {
        get { self[EmbarMaterialKey.self] }
        set { self[EmbarMaterialKey.self] = newValue }
    }
}
