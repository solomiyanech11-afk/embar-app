//
//  Note.swift
//  Embar
//
//  Нотатка — місце, де думки виростають. SPEC.md §11.3
//

import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var title: String = ""
    /// Плейн-дзеркало тіла: пошук, прев'ю картки (110 зн.), matureSticky.
    /// Перезаписується при кожному save із rich-тіла (`contentData`).
    var content: String = ""
    /// Rich-тіло: NSKeyedArchiver-архів NSAttributedString (secure coding).
    /// externalStorage — щоб великий архів жив поруч із базою, не в ній.
    @Attribute(.externalStorage)
    var contentData: Data? = nil
    /// Версія формату архіву: 0 = лише плейн (до-M4), 1 = архів наявний.
    /// Лінива міграція: нотатки з 0 відкриваються з `content` як плейн.
    var contentVersion: Int = 0
    /// Теги з провідним # (як у прототипі). У M4 UI немає — поле незадіяне.
    var tags: [String] = []
    var pinned: Bool = false
    /// Акцентний колір картки: індекс у палітру (nil = без акценту)
    var accentColorIndex: Int? = nil
    /// Банер нотатки: "gradient0".."gradient5" | "photo" | nil (M4)
    var bannerStyle: String? = nil

    // Налаштування вигляду ЦІЄЇ нотатки (SPEC §3.3); nil = дефолт.
    // Тумблери (фокус-режим/мета-рядок/орфографія) — глобальні, в AppStorage.
    /// "large" | "medium" | "normal" | "small"
    var bodySizeRaw: String? = nil
    /// "inter" | "serif" | "mono"
    var bodyFontRaw: String? = nil
    /// "tight" | "normal" | "loose"
    var lineSpacingRaw: String? = nil

    // Провенанс — звідки народилася нотатка (born у прототипі)
    /// "sticky" | "reader" | nil (створена вручну)
    var bornType: String? = nil
    /// Дата стіка-джерела (щоб показати «зі стікера · 12 черв»)
    var bornDate: Date? = nil

    // Зв'язки
    var folder: NoteFolder? = nil
    /// Стік, з якого виросла нотатка. Зворотний бік — Sticker.note
    @Relationship(inverse: \Sticker.note)
    var sourceSticker: Sticker? = nil
    /// Блокнот рідера, з якого народилася нотатка (quoteToNote)
    var sourceBook: ReaderBook? = nil
    /// Нотатки, які ЦЯ нотатка згадує через [[назву]]
    @Relationship(inverse: \Note.mentionedBy)
    var mentions: [Note]? = nil
    /// Backlinks: нотатки, які згадують цю («Тут згадується»)
    var mentionedBy: [Note]? = nil

    /// Інлайн-зображення. cascade: фото належать нотатці й purge-яться з нею.
    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note)
    var images: [NoteImage]? = nil

    init(title: String = "", content: String = "") {
        self.title = title
        self.content = content
    }
}
