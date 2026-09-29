//
//  ReaderUndoLabel.swift
//  Embar
//
//  Ярлик дії для тоста «Скасовано: …» в блокноті рідера (SPEC §4.5).
//
//  Чому enum, а не вільний рядок (i18n 2026-08-03): раніше в pushUndo
//  передавався готовий український текст у родовому відмінку
//  («видалення запису»). Такий рядок не можна перекласти механічно —
//  у кожної мови своя форма слова після двокрапки. Тепер код передає
//  ЩО сталося, а формулювання живе в каталозі перекладів окремо для
//  кожної мови.
//

import Foundation

enum ReaderUndoLabel {
    case addEntry
    case voiceEntry
    case editEntry
    case deleteEntry
    case deleteCover
    case cropPhoto
    case highlight
    case underline
    case removeHighlight
    case removeUnderline
    case addFavorite
    case removeFavorite

    /// Вставка в «Скасовано: %@»
    var text: LocalizedStringResource {
        switch self {
        case .addEntry:
            .init("undo.reader.addEntry", defaultValue: "додавання запису",
                  comment: "Вставка в тост «Скасовано: …»")
        case .voiceEntry:
            .init("undo.reader.voiceEntry", defaultValue: "голосовий запис",
                  comment: "Вставка в тост «Скасовано: …»")
        case .editEntry:
            .init("undo.reader.editEntry", defaultValue: "редагування",
                  comment: "Вставка в тост «Скасовано: …»")
        case .deleteEntry:
            .init("undo.reader.deleteEntry", defaultValue: "видалення запису",
                  comment: "Вставка в тост «Скасовано: …»")
        case .deleteCover:
            .init("undo.reader.deleteCover", defaultValue: "видалення обкладинки",
                  comment: "Вставка в тост «Скасовано: …»")
        case .cropPhoto:
            .init("undo.reader.cropPhoto", defaultValue: "обрізання фото",
                  comment: "Вставка в тост «Скасовано: …»")
        case .highlight:
            .init("undo.reader.highlight", defaultValue: "хайлайт",
                  comment: "Вставка в тост «Скасовано: …»")
        case .underline:
            .init("undo.reader.underline", defaultValue: "підкреслення",
                  comment: "Вставка в тост «Скасовано: …»")
        case .removeHighlight:
            .init("undo.reader.removeHighlight", defaultValue: "прибрати хайлайт",
                  comment: "Вставка в тост «Скасовано: …»")
        case .removeUnderline:
            .init("undo.reader.removeUnderline", defaultValue: "прибрати підкреслення",
                  comment: "Вставка в тост «Скасовано: …»")
        case .addFavorite:
            .init("undo.reader.addFavorite", defaultValue: "додати в обрані",
                  comment: "Вставка в тост «Скасовано: …»")
        case .removeFavorite:
            .init("undo.reader.removeFavorite", defaultValue: "прибрати з обраних",
                  comment: "Вставка в тост «Скасовано: …»")
        }
    }
}
