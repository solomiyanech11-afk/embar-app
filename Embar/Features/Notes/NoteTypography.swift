//
//  NoteTypography.swift
//  Embar
//
//  Єдине місце, де з ролі абзацу + налаштувань нотатки виводяться шрифт і
//  абзацний стиль. У архіві тіла зберігається РОЛЬ, не кегль — тож зміна
//  розміру/інтервалу просто перераховує стилі, не ламаючи документ.
//

import AppKit

/// Базовий кегль тіла (P). H1/H2 фіксовані, S — на два пункти менше за P.
enum BodySizeClass: String, CaseIterable {
    case large, medium, normal, small
    /// Кегль ролі P
    var pSize: CGFloat {
        switch self {
        case .large: return 17
        case .medium: return 15
        case .normal: return 14
        case .small: return 12.5
        }
    }
}

enum NoteLineHeight: String, CaseIterable {
    case tight, normal, loose
    var multiple: CGFloat {
        switch self {
        case .tight: return 1.35
        case .normal: return 1.75
        case .loose: return 2.3
        }
    }
}

/// Шрифт тіла (SPEC §3.3). Прототипні Editorial/Cursive відкладено —
/// їхні сім'ї не бандлимо (§15.2); Serif = Fraunces, Mono = системний.
enum NoteBodyFont: String, CaseIterable {
    case inter, serif, mono
}

/// Налаштування рендеру нотатки (SPEC §3.3). Дефолт = прототип.
struct NoteDocSettings: Equatable {
    var sizeClass: BodySizeClass = .normal
    var lineHeight: NoteLineHeight = .normal
    var font: NoteBodyFont = .inter

    static let `default` = NoteDocSettings()

    init() {}

    /// Прочитати збережені налаштування нотатки (nil-поля → дефолт)
    init(note: Note) {
        sizeClass = note.bodySizeRaw.flatMap(BodySizeClass.init) ?? .normal
        lineHeight = note.lineSpacingRaw.flatMap(NoteLineHeight.init) ?? .normal
        font = note.bodyFontRaw.flatMap(NoteBodyFont.init) ?? .inter
    }
}

enum NoteTypography {
    /// Відступ маркера списку від краю (pt)
    static let listIndent: CGFloat = 22

    // Цитата (редизайн 2026-07-05): риска 2pt кольору ink, зсунута на 4pt
    // від лівого краю; текст — 16pt від риски; Fraunces italic 15/1.6
    static let quoteBarX: CGFloat = 4
    static let quoteBarWidth: CGFloat = 2
    static let quoteTextIndent: CGFloat = 4 + 2 + 16 // риска + її товщина + 16
    static let quoteBarColor = NSColor(embarHex: "#26241f")
    static let quoteTextColor = NSColor(embarHex: "#4a453d")
    static let quoteAuthorColor = NSColor(embarHex: "#a8a39b")

    // Чіп-згадка: текст трохи менший і приглушений (фідбек 2026-07-05)
    static let mentionFontScale: CGFloat = 0.92
    static let mentionTextColor = NSColor(embarHex: "#1a1a1a").withAlphaComponent(0.72)

    /// Основний колір тексту тіла — AppKit-двійник EmbarColors.ink.
    /// Був розсипаний 8 літералами по 6 файлах (code review, reuse)
    static let inkColor = NSColor(embarHex: "#1a1a1a")
    /// Placeholder / приглушений (двійник EmbarColors.ink4)
    static let mutedColor = NSColor(embarHex: "#cccccc")

    // MARK: - Виділення тексту
    //
    // Тон і причини — Theme/SelectionColor.swift (там же і те, як він
    // потрапляє в поля, які ми не малюємо самі). Тут лише псевдоніми,
    // щоб малювання нотаток не тягло чужий тип.
    static var selectionColor: NSColor { EmbarSelection.tint }
    static var selectionColorInactive: NSColor { EmbarSelection.inactive }

    /// Шрифт цитати — Fraunces italic 15 (не залежить від ролі/розміру тіла)
    static func quoteFont() -> NSFont {
        let size: CGFloat = 15
        if let f = NSFont(name: "Fraunces-Italic", size: size) { return f }
        if let f = NSFont(name: "Fraunces Italic", size: size) { return f }
        let desc = NSFontDescriptor(fontAttributes: [.family: "Fraunces Italic"])
        if let f = NSFont(descriptor: desc, size: size),
           f.familyName?.contains("Fraunces") == true { return f }
        return NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }

    /// Абзацний стиль ряду фото: БЕЗ міжрядкового множника — з ним рядок був
    /// би в 1.75× вищий за фото, і знімок «провалювався» до низу рядка з
    /// порожнечею зверху (фідбек 2026-07-05)
    static func photoRowParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1
        style.paragraphSpacing = 4
        style.paragraphSpacingBefore = 4
        return style
    }

    /// Атрибути рядка автора цитати (для M5 quoteToNote): Inter 10.5
    /// uppercase (текст капіталізується при вставці), letter-spacing 0.08em
    static func quoteAuthorAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.headIndent = quoteTextIndent
        style.firstLineHeadIndent = quoteTextIndent
        style.paragraphSpacing = 12
        return [
            .embarQuoteAuthor: NSNumber(value: true),
            .embarRole: ParagraphRole.s.rawValue as NSString,
            .font: NSFont(name: "Inter-Regular", size: 10.5) ?? .systemFont(ofSize: 10.5),
            .kern: 10.5 * 0.08,
            .foregroundColor: quoteAuthorColor,
            .paragraphStyle: style,
        ]
    }

    /// Шрифт для ролі + трейтів. У бандлі лише Light/Regular/Medium/SemiBold
    /// Inter — тож «жирний» = SemiBold, а курсив синтезує NSFontManager
    /// (справжні накреслення можна забандлити пізніше — беклог).
    static func font(role: ParagraphRole, bold: Bool = false, italic: Bool = false,
                     settings: NoteDocSettings = .default) -> NSFont {
        let size: CGFloat
        switch role {
        case .h1: size = 22
        case .h2: size = 17
        case .p:  size = settings.sizeClass.pSize
        case .s:  size = max(settings.sizeClass.pSize - 2.5, 10)
        }
        // Роль дає лише КЕГЛЬ (P2.14): раніше H1/H2 примусово ставали
        // SemiBold, і зняти жирність із заголовка було неможливо — жирність
        // тепер завжди і тільки маркер .embarBold (немає 700 — SemiBold)
        let weight: NSFont.Weight = bold ? .semibold : .regular
        switch settings.font {
        case .inter:
            let base = interFont(size: size, weight: weight)
            return italic ? oblique(base, size: size) : base
        case .serif:
            return frauncesFont(size: size, bold: weight != .regular, italic: italic)
        case .mono:
            let base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            return italic ? oblique(base, size: size) : base
        }
    }

    /// Fraunces для опції «Serif · warm»: справжня italic-сім'я забандлена
    private static func frauncesFont(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let names = italic ? ["Fraunces-Italic", "Fraunces Italic"] : ["Fraunces"]
        var font = names.lazy.compactMap { NSFont(name: $0, size: size) }.first
            ?? .systemFont(ofSize: size)
        if bold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        return font
    }

    /// Синтетичний нахил: у бандлі немає italic-накреслення Inter, тож
    /// застосовуємо зсувну матрицю (shear) до дескриптора шрифту.
    private static func oblique(_ font: NSFont, size: CGFloat) -> NSFont {
        let slant: CGFloat = 0.2
        let m = AffineTransform(m11: size, m12: 0, m21: slant * size, m22: size, tX: 0, tY: 0)
        return NSFont(descriptor: font.fontDescriptor, textTransform: m) ?? font
    }

    private static func interFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let name: String
        switch weight {
        case .light: name = "Inter-Light"
        case .medium: name = "Inter-Medium"
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Абзацний стиль для ролі + списку + цитати + вирівнювання.
    static func paragraphStyle(role: ParagraphRole, list: ListStyle? = nil,
                               quote: Bool = false, alignment: NSTextAlignment = .natural,
                               settings: NoteDocSettings = .default) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineHeightMultiple = settings.lineHeight.multiple
        // Відбій між абзацами — трохи для заголовків
        style.paragraphSpacing = (role == .h1 || role == .h2) ? 6 : 2
        if list != nil {
            style.headIndent = listIndent
            style.firstLineHeadIndent = 0
            style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent)]
        } else if quote {
            style.headIndent = quoteTextIndent
            style.firstLineHeadIndent = quoteTextIndent
            // Цитата реагує на міжряддя нотатки (фідбек Mia 05.09), але
            // тримає власну пропорцію редизайну: при Normal — рівно 1.6
            style.lineHeightMultiple = settings.lineHeight.multiple
                * (1.6 / NoteLineHeight.normal.multiple)
            style.paragraphSpacingBefore = 12
            style.paragraphSpacing = 12
        }
        return style
    }
}
