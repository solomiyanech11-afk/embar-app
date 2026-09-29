//
//  EmbarAttributes.swift
//  Embar
//
//  Семантичні атрибути rich-тіла нотатки (SPEC §11.3). Джерело правди —
//  кастомні ключі `.embar*`; косметика (.foregroundColor/.backgroundColor/
//  шрифт) ставиться поруч для рендеру. Значення кастомних атрибутів — ЛИШЕ
//  NSString/NSNumber, інакше secure-unarchiving архіву тіла ламається.
//

import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// UUID згаданої нотатки (`[[назва]]`) — NSString(uuidString)
    static let embarMention = NSAttributedString.Key("embar.mention")
    /// Жирний — NSNumber(true). Маркер-джерело правди (Inter має лише SemiBold)
    static let embarBold = NSAttributedString.Key("embar.bold")
    /// Курсив — NSNumber(true). Маркер, бо Inter без italic-накреслення —
    /// нахил синтезуємо, а NSFont його не завжди повертає в symbolicTraits
    static let embarItalic = NSAttributedString.Key("embar.italic")
    /// Роль абзацу — NSString "h1"|"h2"|"p"|"s"
    static let embarRole = NSAttributedString.Key("embar.role")
    /// Стиль списку абзацу — NSString "bullet"|"number"|"arrow"|"triangle"
    static let embarList = NSAttributedString.Key("embar.list")
    /// Цитата (blockquote) — NSNumber(true)
    static let embarQuote = NSAttributedString.Key("embar.quote")
    /// Рядок автора цитати — NSNumber(true). Вставляється автоматично при
    /// quoteToNote з Рідера (M5): текст UPPERCASE, префікс «— » кольору ink
    static let embarQuoteAuthor = NSAttributedString.Key("embar.quoteAuthor")
    /// Хайлайт (перо) — NSString слаг кольору
    static let embarHighlight = NSAttributedString.Key("embar.highlight")
    /// Колір тексту — NSString слаг (один із 7)
    static let embarTextColor = NSAttributedString.Key("embar.textColor")
    /// Джерело цитати з Рідера (M5 quoteToNote) — NSString
    /// "bookUUID|entryUUID" на рядку-підписі; клік веде до запису
    static let embarReaderSource = NSAttributedString.Key("embar.readerSource")
    /// Тіло цитати з Рідера — NSNumber(true). Окремий від .embarQuote
    /// вигляд (прототип .qn-quote): СВІТЛА риска ink4 2.5pt, курсив
    /// звичайного шрифту тіла, НЕ Fraunces
    static let embarReaderQuote = NSAttributedString.Key("embar.readerQuote")
}

/// Роль абзацу. Шрифт виводиться з ролі + налаштувань (NoteTypography) —
/// у архіві зберігається роль, не кегль, тож зміна розміру не ламає документ.
enum ParagraphRole: String, CaseIterable {
    case h1, h2, p, s
}

/// Стиль списку. Маркери — літеральні гліфи в тексті (не NSTextList): під
/// TextKit 1 автомаркери не рендеряться, тож малюємо їх самі.
enum ListStyle: String, CaseIterable {
    case bullet, number, arrow, triangle

    /// Гліф маркера для нумерованого — з номером; решта — фіксовані
    func marker(index: Int) -> String {
        switch self {
        case .bullet:   return "•"
        case .number:   return "\(index)."
        case .arrow:    return "→"
        case .triangle: return "▸"
        }
    }
}

/// 4 фіксовані кольори пера — НЕ залежать від палітри (SPEC §13).
enum HighlightColor: String, CaseIterable {
    case yellow, purple, blue, red

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(embarHex: "#fbe6a0")
        case .purple: return NSColor(embarHex: "#d9c9f0")
        case .blue:   return NSColor(embarHex: "#c5dbf4")
        case .red:    return NSColor(embarHex: "#f4c8c8")
        }
    }
}

/// 7 кольорів тексту з прототипу (`fmtNoteColor`). Дефолт (ink) = без слага.
enum BodyTextColor: String, CaseIterable {
    case ink, red, orange, lime, blue, purple, pink

    var nsColor: NSColor {
        switch self {
        case .ink:    return NSColor(embarHex: "#1a1a1a")
        case .red:    return NSColor(embarHex: "#fca5a5")
        case .orange: return NSColor(embarHex: "#fdba74")
        case .lime:   return NSColor(embarHex: "#a3e635")
        case .blue:   return NSColor(embarHex: "#93c5fd")
        case .purple: return NSColor(embarHex: "#d8b4fe")
        case .pink:   return NSColor(embarHex: "#f9a8d4")
        }
    }
}

extension NSColor {
    /// NSColor з hex — делегує єдиному парсеру Color(hex:) (ColorHex.swift):
    /// дубль логіки розходився б із SwiftUI-стороною (code review, reuse)
    convenience init(embarHex hex: String) {
        self.init(Color(hex: hex))
    }
}
