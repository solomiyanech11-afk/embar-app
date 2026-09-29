//
//  ReaderTheme.swift
//  Embar
//
//  Тема блокнота рідера (2026-07-21, «теми замість сторінок»): назване
//  русло, під яке пишуться нові записи, поки тема активна. Окрема
//  сутність, а не рядок на записі: перейменування — одна операція,
//  ідентичність стабільна (без колізій імен), майбутнє згортання списку
//  тем (BACKLOG) потребує перелічуваних сутностей, soft-delete як у всіх.
//
//  CloudKit-правила: всі поля з default, без @Attribute(.unique),
//  звʼязки optional з inverse.
//

import Foundation
import SwiftData

@Model
final class ReaderTheme {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var name: String = ""
    /// Одна активна тема на блокнот максимум — інваріант тримає
    /// ReaderService (activateTheme деактивує решту)
    var isActive: Bool = false

    // Зв'язки
    /// Блокнот-власник. Зворотний бік — ReaderBook.themes (cascade)
    var book: ReaderBook? = nil
    /// Записи теми. nullify: тема зникає — записи лишаються в потоці
    @Relationship(deleteRule: .nullify, inverse: \ReaderEntry.theme)
    var entries: [ReaderEntry]? = nil

    init(name: String = "") {
        self.name = name
    }
}
