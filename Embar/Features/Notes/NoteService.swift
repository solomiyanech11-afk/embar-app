//
//  NoteService.swift
//  Embar
//
//  Операції над нотатками (SPEC §3, §11.3, §12). Чисті дата-операції над
//  ModelContext; тости показує View. Видалення = soft-delete (deletedAt),
//  фізична чистка > 30 днів в AppMaintenance.
//

import Foundation
import SwiftData

enum NoteService {

    // MARK: - Створення

    /// Створити порожню нотатку в поточній папці (Enter у композері).
    @discardableResult
    static func add(title: String = "", folder: NoteFolder? = nil,
                    in context: ModelContext) -> Note {
        let note = Note(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        note.folder = folder
        context.insert(note)
        NoteMutation.changed(note) // кеш списку (F5.4)
        return note
    }

    /// Створити/знайти папку за назвою (інлайн-створення «Нова папка»).
    /// Дублікати за назвою не плодимо — повертаємо наявну.
    @discardableResult
    static func createFolder(_ name: String, existing: [NoteFolder],
                             in context: ModelContext) -> NoteFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let match = existing.first(where: { $0.name == trimmed && $0.deletedAt == nil }) {
            return match
        }
        let folder = NoteFolder(name: trimmed)
        context.insert(folder)
        return folder
    }

    // MARK: - Стан

    static func togglePin(_ note: Note) {
        note.pinned.toggle()
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4)
    }

    static func setFolder(_ folder: NoteFolder?, for note: Note) {
        note.folder = folder
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4)
    }

    static func setAccent(_ index: Int?, for note: Note) {
        note.accentColorIndex = index
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4): updatedAt у сорті
    }

    // MARK: - Видалення (soft-delete + undo)

    static func softDelete(_ note: Note) {
        note.deletedAt = .now
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4)
    }

    static func undoDelete(_ note: Note) {
        note.deletedAt = nil
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4)
    }

    // MARK: - Backlinks / mentions (SPEC §11.3, §12.4)

    /// Нотатка за id (для чіпів-згадок; повертає і soft-deleted — рішення
    /// про тост/навігацію ухвалює View)
    static func find(_ id: UUID, in context: ModelContext) -> Note? {
        var d = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Синхронізувати збережений зв'язок mentions зі списком UUID, знайдених
    /// у тілі при save (SPEC §11.3: без глобальних ре-сканів, O(чіпів)).
    /// Soft-deleted згадані ЛИШАЮТЬСЯ у зв'язку (undo-безпечно, §12.5).
    static func syncMentions(_ ids: Set<UUID>, for note: Note, in context: ModelContext) {
        let current = Set((note.mentions ?? []).map(\.id))
        guard ids != current else { return }
        note.mentions = ids.compactMap { find($0, in: context) }
        // інверс mentionedBy оновлюється автоматично
    }
}
