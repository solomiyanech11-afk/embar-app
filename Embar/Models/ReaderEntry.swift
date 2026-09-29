//
//  ReaderEntry.swift
//  Embar
//
//  Запис у блокноті рідера. SPEC.md §11.5
//

import Foundation
import SwiftData

/// Тип запису (SPEC §11.5: note/thought прототипу уніфіковано в thought)
enum ReaderEntryKind: String {
    case thought
    case quote
    case question
    case insight
    case voice
}

@Model
final class ReaderEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    /// Зберігаємо як String (CloudKit-дружньо); типізований доступ — через `kind`
    var type: String = ReaderEntryKind.thought.rawValue
    var text: String = ""
    /// Лише для цитат
    var author: String? = nil
    /// ⚠️ DEPRECATED (2026-07-21, «теми замість сторінок»): сторінки
    /// прибрано з продукту. Поле лишається в схемі за CloudKit-правилами
    /// (additive-only) — ніде не читається і не пишеться
    var page: String? = nil
    @Attribute(.externalStorage)
    var photoData: Data? = nil
    /// Лише для голосових
    @Attribute(.externalStorage)
    var audioData: Data? = nil
    /// Тривалість голосового, сек
    var audioDuration: Double? = nil
    var favorite: Bool = false

    // Зв'язки
    @Relationship(deleteRule: .cascade, inverse: \Highlight.entry)
    var highlights: [Highlight]? = nil
    var book: ReaderBook? = nil
    /// Тема, під якою написано запис (2026-07-21). Зворотний бік —
    /// ReaderTheme.entries; nil = загальний потік
    var theme: ReaderTheme? = nil

    /// Теги НЕ зберігаються окремо — парсяться з text регексом #… (як у прототипі)
    var kind: ReaderEntryKind {
        get { ReaderEntryKind(rawValue: type) ?? .thought }
        set { type = newValue.rawValue }
    }

    init(kind: ReaderEntryKind = .thought, text: String = "") {
        self.type = kind.rawValue
        self.text = text
    }
}
