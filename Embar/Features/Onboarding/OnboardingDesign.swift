//
//  OnboardingDesign.swift
//  Embar
//
//  Токени знайомства — окремий візуальний світ, і це свідомо.
//  Панель Embar живе в теплому молоці (#fcfbf9) з чорнилом; перше вікно
//  за хендофом «Проявник» — мʼята зі скляною шторою і кораловим
//  акцентом. Тому ці кольори НЕ в EmbarColors: вони не мають протікати
//  на поверхні продукту, де діє звичайна палітра.
//
//  Джерело: docs/design_handoff_embar_onboarding (варіант G), розділ
//  «Design Tokens».
//

import SwiftUI

enum OnboardingDesign {
    // MARK: - Розміри вікна

    static let width: CGFloat = 660
    static let height: CGFloat = 440
    /// Радіус самого вікна. 32 → 16 (рішення 2026-09-27, SPEC §15.78е):
    /// стандартне місце системної кнопки закриття стає концентричним із
    /// дугою кута - наведення і клік нативні. Той самий кут, що в панелі
    static let windowRadius: CGFloat = 16
    /// Відступ скляної шторки від країв вікна
    static let inset: CGFloat = 18
    /// Радіус шторки
    static let glassRadius: CGFloat = 28

    // MARK: - Кольори

    /// Мʼятне тло вікна
    static let bg = Color(hex: "#E9F3F1")
    /// Основний текст
    static let ink = Color(hex: "#16211F")
    /// Вторинний текст (тагляйн, підзаголовки, підписи)
    static let inkSoft = Color(hex: "#16211F").opacity(0.6)
    /// Кораловий акцент — знак, повзунок, головні кнопки, смуга краю.
    ///
    /// ❗ Ревізія 2026-08-17: тут був власний #F93B3B із дизайн-хендофа —
    /// третій «брендовий» червоний у продукті. Тепер це РІВНО той самий
    /// токен, що знак у хедері та іконка: один бренд-червоний на все.
    /// Назви coral*/coralFill лишились — вони описують візуальну мову
    /// знайомства, але значення приходить з EmbarColors
    static let coral = EmbarColors.brandRed
    static let coralLight = EmbarColors.brandRedLight

    /// Мʼятний — другий колір світіння на краю. Це фон знайомства
    /// (#E9F3F1), поглиблений до насиченості, з якої виходить світло:
    /// той самий відтінок, але видимий на темному столі
    static let glowMint = Color(hex: "#7FD4C0")

    /// Градієнт коралових кнопок і повзунка (CSS 150deg)
    static let coralFill = LinearGradient(
        colors: [coralLight, coral],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: - Скло

    /// Заливка шторки поверх розмитої копії тла
    static let glassTint = Color.white.opacity(0.38)
    /// Білий кант скла
    static let glassStroke = Color.white.opacity(0.8)
    /// CSS blur(46px) ≈ .blur(radius: 23) — SwiftUI бере радіус як σ
    static let backdropBlur: CGFloat = 23
    /// Заливка пігулок (поле імені, скляні кнопки)
    static let pillFill = Color.white.opacity(0.5)
    static let pillStroke = Color.white.opacity(0.85)

    /// Ширина пояснювальних текстів у тактах. ОДНА на всі: 380 - єдине
    /// значення, за якого і жест, і стіки лягають у два рядки обома
    /// мовами. Вузьче лишало самотнє слово на третьому рядку («own.»,
    /// потім «them.»), ширше - самотнє слово українською.
    /// Заміряно NSLayoutManager-ом на Inter 15, закріплено
    /// тестом OnboardingWrapTests
    static let bodyTextWidth: CGFloat = 380

    // MARK: - Мотон

    /// Основна крива хендофу — cubic-bezier(0.22, 1, 0.36, 1)
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// Пауза перед авто-інтро шторки
    static let introDelay: Duration = .milliseconds(900)
    static let introDuration: Double = 0.7
}
