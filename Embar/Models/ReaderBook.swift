//
//  ReaderBook.swift
//  Embar
//
//  Блокнот рідера — шар анотацій над одним джерелом. SPEC.md §11.7
//

import Foundation
import SwiftData

@Model
final class ReaderBook {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    /// Бампається при кожній зміні записів — полиця сортується за цим
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var title: String = ""
    /// Фото-обкладинка (externalStorage: великі дані зберігаються поруч з базою, не в ній)
    @Attribute(.externalStorage)
    var photoData: Data? = nil
    var coverColorIndex: Int = 0
    /// Форма картки на полиці: "tall" | "square"
    var shape: String? = nil
    var folderName: String? = nil

    // Зв'язки. cascade: джерела й записи належать блокноту і видаляються разом з ним
    @Relationship(deleteRule: .cascade, inverse: \ReaderSource.book)
    var sources: [ReaderSource]? = nil
    @Relationship(deleteRule: .cascade, inverse: \ReaderEntry.book)
    var entries: [ReaderEntry]? = nil
    /// Теми блокнота (2026-07-21): належать блокноту, йдуть разом з ним
    @Relationship(deleteRule: .cascade, inverse: \ReaderTheme.book)
    var themes: [ReaderTheme]? = nil
    /// Нотатки, народжені з цього блокнота (quoteToNote) — живуть незалежно, без cascade
    @Relationship(inverse: \Note.sourceBook)
    var bornNotes: [Note]? = nil

    init(title: String = "") {
        self.title = title
    }

    /// Живе джерело link-bar (заміна робить soft-delete старого)
    var activeSource: ReaderSource? {
        sources?.first { $0.deletedAt == nil }
    }

    /// Активна тема (максимум одна — інваріант тримає ReaderService)
    var activeTheme: ReaderTheme? {
        themes?.first { $0.isActive && $0.deletedAt == nil }
    }
}
