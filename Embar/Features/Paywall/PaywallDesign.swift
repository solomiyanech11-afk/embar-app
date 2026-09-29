//
//  PaywallDesign.swift
//  Embar
//
//  Токени пейвола - редизайн «glass» за design_handoff_paywall
//  (2026-09-17, high-fidelity). Темний фон із мʼякими світіннями,
//  скляний модал, дві скляні картки планів, один CTA.
//
//  Свідомі заміни відносно хендофа (правила проєкту сильніші):
//  · Newsreader → Fraunces (emDisplay) - експеримент із бренд-серифом
//    закрито, Fraunces лишається;
//  · SF Pro → Inter (emUI) - шрифт UI всього застосунку;
//  · акцент #FF3B47 → EmbarColors.brandRed #FE3B43 - канон двох
//    червоних (SPEC §15.53), третього не заводимо.
//  Розміри масштабовано з макетних 880pt ширини до вікна 700pt.
//

import SwiftUI

enum PaywallDesign {
    // MARK: - Вікно (саме вікно і є модалом; тьмяна «сторінка» з
    // хендофа не потрібна - за вікном живий робочий стіл)

    static let width: CGFloat = 640
    /// Висота порахована з метрик Inter/Fraunces (замір 2026-09-17), а не
    /// на око. Найвищий стан - trial минув, українською: шапка 194 +
    /// 20 + картка 308 + 20 + CTA 48 + 12 + рядок плану 14 + 12 +
    /// підказка «Поки ви вирішуєте…» 28 + зазор ≥ 8 + футер 32 + 22 =
    /// 718. Менше 720 вміст не вміщається; до 640 без викидання рядків
    /// не дійти
    static let height: CGFloat = 720
    /// 32 → 16 (рішення 2026-09-27, SPEC §15.78е): стандартне місце
    /// системної кнопки закриття (центр 16, 16) стає концентричним із
    /// дугою кута - наведення і клік нативні. Той самий кут, що в панелі
    static let windowRadius: CGFloat = 16
    /// Ширина текстових блоків шапки: підзаголовок мусить лягати у ДВА
    /// рядки обома мовами навіть із трицифровим лічильником думок
    static let headerTextWidth: CGFloat = 524
    /// Відступи модала: 44 зверху/з боків, 30 знизу (хендоф 56/36,
    /// стиснуто під вікно)
    static let inset: CGFloat = 36
    static let bottomInset: CGFloat = 22

    // MARK: - Поверхні (хендоф: сторінка #0A0B0E + скло білим)

    /// СВІТЛЕ скло (фідбек 2026-09-17): фон - спільний BehindWindowGlass
    /// (чистий blur+saturate без молока), поверх - лише ледь помітний
    /// темний серпанок для читабельності білого тексту
    static let bg = Color(hex: "#0A0B0E")
    static let bgTintOpacity: CGFloat = 0.18
    /// Скляна заливка модала поверх тінту
    static let glassWash = Color.white.opacity(0.06)
    static let modalBorder = Color.white.opacity(0.55)

    static let cardRadius: CGFloat = 24
    /// Картка плану: фіксована висота = вміст місячної картки українською
    /// (найвищої) + 1pt: 20 + назва 15 + ціна 37 + слот приміток 41 +
    /// лінія 1 + три пункти 90 + рядок вибору 15 + 16 + 7 проміжків × 12
    /// = 307. Обидві картки однакової висоти, лінії-роздільники на
    /// одному рівні завдяки слоту приміток
    static let cardHeight: CGFloat = 308
    static let cardSpacing: CGFloat = 12
    /// Слот під ціною: «Скасувати можна будь-коли» (14) + 3 + рядок про
    /// поновлення 10pt у два рядки (24). Однаковий в обох картках і обома
    /// мовами, щоб лінії-роздільники стояли на одному рівні
    static let cardNoteSlot: CGFloat = 41
    static let cardBg = Color.white.opacity(0.1)
    static let cardBorder = Color.white.opacity(0.38)
    static let cardSelectedBorder = Color.white.opacity(0.95)
    static let divider = Color.white.opacity(0.25)

    // MARK: - Текст (білий з альфами хендофа)

    static let text = Color.white
    static let text85 = Color.white.opacity(0.85)
    static let text75 = Color.white.opacity(0.75)
    static let text65 = Color.white.opacity(0.65)
    static let text60 = Color.white.opacity(0.6)
    static let text55 = Color.white.opacity(0.55)
    static let text50 = Color.white.opacity(0.5)
    static let text40 = Color.white.opacity(0.4)
    static let text35 = Color.white.opacity(0.35)

    // MARK: - Акценти

    /// Канонічний бренд-червоний, НЕ #FF3B47 із хендофа
    static let accent = EmbarColors.brandRed
    /// Бірюзове світіння знизу - rgb(120,200,215) із хендофа,
    /// суто декоративне
    static let tealGlow = Color(red: 120 / 255, green: 200 / 255,
                                blue: 215 / 255)

    // MARK: - Мотон

    /// Перемикання карток - 250ms ease (хендоф)
    static let select = Animation.easeInOut(duration: 0.25)
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
}
