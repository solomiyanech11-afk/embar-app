//
//  StickyInk.swift
//  Embar
//
//  Контрастні токени тексту НА поверхні стіка (SPEC §15.57).
//
//  Було (прототип applyStickyContrast): фіксовані чорні альфи
//  0.85/0.60/0.45 «контраст вирішує палітра». Заміри 2026-08-20 показали,
//  що не вирішує: сірі капшни падали до 1.0–2.7:1, і навіть основний
//  текст провалювався на найтемніших слотах. Рішення користувача —
//  адаптивне чорнило: для кожного кольору стіка альфи ДОБИРАЮТЬСЯ до
//  WCAG 4.5:1 (мінімуми — прототипні 0.85/0.60/0.45, щоб пастельні стіки
//  не потемніли без потреби); на темних стіках (нині лише Ponyo-5)
//  чорнило перевертається в біле. Це свідомий відхід від прототипу.
//
//  Єдине джерело для StickyCard, StickyExpandedView, тулбара і віджетів.
//

import AppKit
import SwiftUI

enum StickyInk {

    /// Набір чорнил, підібраний під конкретний колір стіка
    struct Tokens {
        /// Основний текст на стіку
        let ink: Color
        /// Вторинний (мета, лейбли дій)
        let ink2: Color
        /// Третинний (капшни, час, плейсхолдери)
        let ink3: Color
        /// Фон кнопок на поверхні стіка
        let buttonBg: Color
        let buttonBgHover: Color
        /// Стік темний — накладки мусять світлішати, а не темніти
        let onDark: Bool

        /// Тонована накладка на поверхні стіка: підкладка поля вводу,
        /// підсвітка вибраного, неактивна пігулка.
        ///
        /// ❗ Це НЕ те саме, що `buttonBg`: ваги тут різні й задані
        /// дизайном (0.04 / 0.06 / 0.1). Прямий `Color.black.opacity(…)`
        /// на поверхні стіка заборонений — на темному стіку (нині Ponyo-5)
        /// чорна підкладка зливається з фоном, і поле деталей втрачало
        /// афорданс «сюди можна писати», а підсвітка вибраного емоджі була
        /// просто невидима (ревʼю 2026-08-20). Альфа на світлому лишається
        /// прототипною до останнього знака; на темному піднімається в тій
        /// самій пропорції, що й `buttonBg` (0.08 → 0.12)
        func wash(_ alpha: Double) -> Color {
            onDark ? .white.opacity(alpha * 1.5) : .black.opacity(alpha)
        }
    }

    /// Червоний дедлайна = ЄДИНИЙ danger-токен (ревізія 2026-08-17).
    /// Лишається тут як зручна назва для поверхні стіка; значення —
    /// одне для всього продукту, правити тільки в EmbarColors.danger
    static let deadlineRed = EmbarColors.danger

    /// Прототипні альфи — вони ж мінімуми адаптивного добору
    private static let floors = (ink: 0.85, ink2: 0.60, ink3: 0.45)

    /// Цільовий контраст дрібного тексту (WCAG AA)
    private static let targetRatio = 4.5

    // MARK: - Добір

    /// Чорнила під колір стіка. Кольорів у палітрах скінченно — результат
    /// кешується, тож геометрія добору рахується один раз на колір
    static func on(_ background: Color) -> Tokens {
        guard let rgb = sRGB(of: background) else { return fallback }
        let key = cacheKey(rgb)
        if let cached = cache[key] { return cached }
        let tokens = resolve(rgb)
        cache[key] = tokens
        return tokens
    }

    private static var cache: [String: Tokens] = [:]

    /// Прототипні значення — якщо колір не сконвертувався в sRGB
    private static var fallback: Tokens {
        Tokens(ink: .black.opacity(floors.ink),
               ink2: .black.opacity(floors.ink2),
               ink3: .black.opacity(floors.ink3),
               buttonBg: .black.opacity(0.08),
               buttonBgHover: .black.opacity(0.16),
               onDark: false)
    }

    private static func resolve(_ bg: RGB) -> Tokens {
        // Темний стік: біле чорнило читається краще за будь-яке чорне
        if contrast(white, bg) > contrast(black, bg),
           contrast(blend(black, over: bg, alpha: 1), bg) < targetRatio {
            let a3 = minAlpha(of: white, over: bg, floor: 0.62)
            let a2 = min(1, max(0.78, a3 + 0.13))
            let a1 = min(1, max(0.92, a2 + 0.10))
            return Tokens(ink: .white.opacity(a1),
                          ink2: .white.opacity(a2),
                          ink3: .white.opacity(a3),
                          buttonBg: .white.opacity(0.12),
                          buttonBgHover: .white.opacity(0.22),
                          onDark: true)
        }
        // Світлий/насичений: чорна альфа, як у прототипі, але не нижча за
        // ту, що дає 4.5:1 на саме цьому кольорі
        let a3 = minAlpha(of: black, over: bg, floor: floors.ink3)
        let a2 = min(1, max(floors.ink2, a3 + 0.13))
        let a1 = min(1, max(floors.ink, a2 + 0.12))
        return Tokens(ink: .black.opacity(a1),
                      ink2: .black.opacity(a2),
                      ink3: .black.opacity(a3),
                      buttonBg: .black.opacity(0.08),
                      buttonBgHover: .black.opacity(0.16),
                      onDark: false)
    }

    /// Найменша альфа чорнила, з якою суміш «чорнило поверх стіка» тримає
    /// цільовий контраст із самим стіком. Крок 0.01 — точності ока досить
    static func minAlpha(of fg: RGB, over bg: RGB, floor: Double) -> Double {
        var alpha = floor
        while alpha < 1 {
            if contrast(blend(fg, over: bg, alpha: alpha), bg) >= targetRatio {
                return alpha
            }
            alpha += 0.01
        }
        return 1
    }

    // MARK: - Колірна арифметика (WCAG)

    typealias RGB = (r: Double, g: Double, b: Double)

    static let black: RGB = (0, 0, 0)
    static let white: RGB = (1, 1, 1)

    static func sRGB(of color: Color) -> RGB? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent))
    }

    static func blend(_ fg: RGB, over bg: RGB, alpha: Double) -> RGB {
        (fg.r * alpha + bg.r * (1 - alpha),
         fg.g * alpha + bg.g * (1 - alpha),
         fg.b * alpha + bg.b * (1 - alpha))
    }

    /// Відносна яскравість за WCAG 2.x
    static func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func cacheKey(_ c: RGB) -> String {
        "\(Int(c.r * 255))-\(Int(c.g * 255))-\(Int(c.b * 255))"
    }
}
