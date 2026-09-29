//
//  NoteListSlice.swift
//  Embar
//
//  Кеш списку нотаток (F5, пункт 4). Той самий механізм, що
//  StickyWallSlice для стіни, і з тих самих причин: `notes.sorted` на
//  5000 коштував 447 мс при відкритті і ще по ~275 мс ПІД ЧАС СКРОЛУ,
//  бо кожен прохід body заново матеріалізує всі обʼєкти @Query.
//
//  Відмінність від стіни — ПОШУК. Він читає title/content, тобто саме
//  ті поля, які найчастіше міняються і найдорожче тримати в зліпках
//  (тіла нотаток бувають довгі). Тому кеш тримає зріз ПАПКИ (членство +
//  порядок), а пошук накладається зверху на вже відсортований масив:
//  фільтр порядку не міняє, а сканувати доводиться лише те, що в папці.
//  Наслідок, який робить механізм дешевим: набір тексту в редакторі
//  (title/content) кеш НЕ інвалідує — лише `updatedAt`, бо він у сорті.
//

import Foundation
import SwiftData

// MARK: - Сповіщення про мутації нотаток

extension Notification.Name {
    /// Одна нотатка змінилась (object = Note) → точковий патч кеша
    static let embarNoteMutated = Notification.Name("embarNoteMutated")
    /// Масова зміна (обслуговування, сідери) → повна інвалідація
    static let embarNotesBulkChanged = Notification.Name("embarNotesBulkChanged")
}

/// Єдина точка посту — пара до StickerMutation
enum NoteMutation {
    static func changed(_ note: Note) {
        NotificationCenter.default.post(name: .embarNoteMutated, object: note)
    }

    static func bulkChanged() {
        NotificationCenter.default.post(name: .embarNotesBulkChanged, object: nil)
    }
}

// MARK: - Зліпок залежностей списку

/// Поля, від яких залежать членство в папці, порядок і лічильники.
/// ❗ title/content сюди НЕ входять — див. шапку файлу
struct NoteSnapshot: Equatable {
    var id: UUID
    var folderID: UUID?
    var deleted: Bool
    var pinned: Bool
    var updatedAt: Date

    init(_ n: Note) {
        id = n.id
        folderID = n.folder?.id
        deleted = n.deletedAt != nil
        pinned = n.pinned
        updatedAt = n.updatedAt
    }

    func matches(folderID selected: UUID?) -> Bool {
        guard !deleted else { return false }
        if let selected { return folderID == selected }
        return true
    }

    /// Живі нотатки рахуються незалежно від вибраної папки
    var countable: Bool { !deleted }

    /// Канонічний тотальний порядок: закріплені вгорі, далі новіші,
    /// тайбрейк за id (без нього звірка кеша з еталоном неможлива —
    /// та сама причина, що в StickySnapshot)
    static func order(_ a: Self, _ b: Self) -> Bool {
        if a.pinned != b.pinned { return a.pinned }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id.uuidString < b.id.uuidString
    }
}

/// Зріз списку: нотатки папки в порядку показу + лічильники чіпів
struct NoteListSlice {
    var items: [Note] = []
    var countAll: Int = 0
    var countByFolder: [UUID: Int] = [:]
}

// MARK: - Двигун

@MainActor
final class NoteListSliceEngine {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md

    private(set) var slice = NoteListSlice()
    private(set) var folderID: UUID??
    private var snapshots: [ObjectIdentifier: NoteSnapshot] = [:]

    /// Один прохід по всіх нотатках: зліпки + членство + лічильники
    func rebuild(all: [Note], folderID selected: UUID?) {
        var snaps: [ObjectIdentifier: NoteSnapshot] = [:]
        snaps.reserveCapacity(all.count)
        var matched: [(Note, NoteSnapshot)] = []
        var countAll = 0
        var countByFolder: [UUID: Int] = [:]
        for note in all {
            let snap = NoteSnapshot(note)
            snaps[ObjectIdentifier(note)] = snap
            if snap.countable {
                countAll += 1
                if let id = snap.folderID { countByFolder[id, default: 0] += 1 }
            }
            if snap.matches(folderID: selected) { matched.append((note, snap)) }
        }
        matched.sort { NoteSnapshot.order($0.1, $1.1) }
        slice = NoteListSlice(items: matched.map(\.0), countAll: countAll,
                              countByFolder: countByFolder)
        snapshots = snaps
        folderID = .some(selected)
    }

    /// Точковий патч: прибрати зі старої позиції, вставити в нову
    func update(_ note: Note) {
        guard let selected = folderID else { return } // кеш ще не будувався
        let key = ObjectIdentifier(note)
        let old = snapshots[key]
        // Фізично видалений @Model: властивостей не торкатися (краш).
        // isDeleted живе лише ДО save, після — обʼєкт випадає з контексту
        let purged = note.isDeleted || note.modelContext == nil
        let new: NoteSnapshot? = purged ? nil : NoteSnapshot(note)

        if old?.countable == true {
            slice.countAll -= 1
            if let id = old?.folderID {
                let left = (slice.countByFolder[id] ?? 0) - 1
                slice.countByFolder[id] = left > 0 ? left : nil
            }
        }
        if let new, new.countable {
            slice.countAll += 1
            if let id = new.folderID { slice.countByFolder[id, default: 0] += 1 }
        }

        if old?.matches(folderID: selected) == true,
           let i = slice.items.firstIndex(where: { $0 === note }) {
            slice.items.remove(at: i)
        }
        if let new {
            snapshots[key] = new
            if new.matches(folderID: selected) { insert(note, snap: new) }
        } else {
            snapshots.removeValue(forKey: key)
        }
    }

    /// Бінарна вставка; ключі сусідів — зі зліпків (без матеріалізації)
    private func insert(_ note: Note, snap: NoteSnapshot) {
        var lo = 0, hi = slice.items.count
        while lo < hi {
            let mid = (lo + hi) / 2
            guard let midSnap = snapshots[ObjectIdentifier(slice.items[mid])] else {
                lo = slice.items.count
                break
            }
            if NoteSnapshot.order(midSnap, snap) { lo = mid + 1 } else { hi = mid }
        }
        slice.items.insert(note, at: lo)
    }

    // MARK: Звірка (запобіжник пісочниці + тести)

    func divergence(from reference: NoteListSlice) -> String? {
        if slice.items.count != reference.items.count {
            return "items: у кеші \(slice.items.count), в еталоні \(reference.items.count)"
        }
        for i in slice.items.indices where slice.items[i] !== reference.items[i] {
            return "items[\(i)]: у кеші «\(preview(slice.items[i]))», " +
                   "в еталоні «\(preview(reference.items[i]))»"
        }
        if slice.countAll != reference.countAll {
            return "countAll: у кеші \(slice.countAll), в еталоні \(reference.countAll)"
        }
        if slice.countByFolder != reference.countByFolder {
            return "countByFolder розійшовся: кеш \(slice.countByFolder), " +
                   "еталон \(reference.countByFolder)"
        }
        return nil
    }

    private func preview(_ note: Note) -> String {
        guard !note.isDeleted, note.modelContext != nil else { return "purged @Model" }
        return "\(note.id.uuidString.prefix(8))·\(note.title.prefix(16))"
    }

    /// Еталонний перерахунок без мутації стану двигуна
    static func computeReference(all: [Note], folderID: UUID?) -> NoteListSlice {
        let scratch = NoteListSliceEngine()
        scratch.rebuild(all: all, folderID: folderID)
        return scratch.slice
    }
}
