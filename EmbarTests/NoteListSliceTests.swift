//
//  NoteListSliceTests.swift
//  EmbarTests
//
//  Кеш списку нотаток (F5, пункт 4) — пара до StickyWallSliceTests.
//  Головне: точковий патч після кожної мутації == повний перерахунок
//  (та сама звірка, що запобіжник пісочниці в NotesModel).
//

import XCTest
import SwiftData
@testable import Embar

final class NoteListSliceTests: XCTestCase {

    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func fetchAll(_ context: ModelContext) throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    private func seed(_ context: ModelContext, folders: [NoteFolder],
                      count: Int, rng: inout SeededRNG) -> [Note] {
        let base = Date.now
        var out: [Note] = []
        for i in 0..<count {
            let n = Note()
            n.title = "Нотатка #\(i)"
            n.content = "Тіло нотатки номер \(i)"
            n.createdAt = base.addingTimeInterval(-Double(i))
            n.updatedAt = n.createdAt
            n.pinned = Int.random(in: 0..<8, using: &rng) == 0
            if Int.random(in: 0..<9, using: &rng) == 0 { n.deletedAt = base }
            if Int.random(in: 0..<3, using: &rng) == 0 {
                n.folder = folders.randomElement(using: &rng)
            }
            context.insert(n)
            out.append(n)
        }
        return out
    }

    // MARK: - Головний тест: патч ↔ перерахунок

    func testRandomizedPatchMatchesFullRecompute() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 20260828)
        let folders = [NoteFolder(name: "Ідеї"), NoteFolder(name: "Робота")]
        folders.forEach(context.insert)
        let notes = seed(context, folders: folders, count: 120, rng: &rng)

        for selected in [nil, folders[0].id, folders[1].id] as [UUID?] {
            let engine = NoteListSliceEngine()
            engine.rebuild(all: try fetchAll(context), folderID: selected)

            for step in 0..<200 {
                let note = notes.randomElement(using: &rng)!
                guard !note.isDeleted else { continue }
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: note.pinned.toggle(); note.updatedAt = .now
                case 1: note.deletedAt = note.deletedAt == nil ? .now : nil
                case 2: note.folder = folders.randomElement(using: &rng)
                case 3: note.folder = nil
                default: note.updatedAt = .now // збереження редактора
                }
                engine.update(note)
                let reference = NoteListSliceEngine.computeReference(
                    all: try fetchAll(context), folderID: selected)
                if let divergence = engine.divergence(from: reference) {
                    XCTFail("Крок \(step), папка \(selected != nil): \(divergence)")
                    return
                }
            }
        }
    }

    /// Нова нотатка (композер / matureSticky) — вставка патчем нагору
    func testInsertOfUnknownNotePatches() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 3)
        let folders = [NoteFolder(name: "Ідеї")]
        folders.forEach(context.insert)
        _ = seed(context, folders: folders, count: 30, rng: &rng)

        let engine = NoteListSliceEngine()
        engine.rebuild(all: try fetchAll(context), folderID: nil)

        let fresh = Note()
        fresh.title = "щойно з композера"
        context.insert(fresh)
        engine.update(fresh)

        let reference = NoteListSliceEngine.computeReference(
            all: try fetchAll(context), folderID: nil)
        XCTAssertNil(engine.divergence(from: reference))
        XCTAssertTrue(engine.slice.items.first { !$0.pinned } === fresh)
    }

    /// Фізично видалена нотатка: без краша і без сліду в зрізі
    func testPurgedNoteIsRemoved() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 42)
        let folders = [NoteFolder(name: "Ідеї")]
        folders.forEach(context.insert)
        let notes = seed(context, folders: folders, count: 20, rng: &rng)

        let engine = NoteListSliceEngine()
        engine.rebuild(all: try fetchAll(context), folderID: nil)

        let victim = notes.first { $0.deletedAt == nil }!
        context.delete(victim)
        try context.save()
        engine.update(victim)

        let reference = NoteListSliceEngine.computeReference(
            all: try fetchAll(context), folderID: nil)
        XCTAssertNil(engine.divergence(from: reference))
        XCTAssertFalse(engine.slice.items.contains { $0 === victim })
    }

    /// Порядок: закріплені вгорі, далі новіші за updatedAt
    func testPinnedFirstThenNewest() throws {
        let context = try makeContext()
        let base = Date.now
        let fresh = Note(); fresh.title = "свіжа"; fresh.updatedAt = base
        let pinnedOld = Note(); pinnedOld.title = "закріплена стара"
        pinnedOld.updatedAt = base.addingTimeInterval(-500)
        pinnedOld.pinned = true
        [fresh, pinnedOld].forEach(context.insert)

        let engine = NoteListSliceEngine()
        engine.rebuild(all: try fetchAll(context), folderID: nil)
        XCTAssertTrue(engine.slice.items.first === pinnedOld)
    }

    /// Наскрізно: мутації через NoteService доходять до кеша моделі
    func testModelSliceStaysFreshThroughServiceMutations() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 5)
        let folders = [NoteFolder(name: "Ідеї")]
        folders.forEach(context.insert)
        let notes = seed(context, folders: folders, count: 40, rng: &rng)

        let model = NotesModel()
        var snapshot = try fetchAll(context)
        _ = model.slice(all: snapshot) // збудувати кеш

        NoteService.togglePin(notes.first { $0.deletedAt == nil }!)
        NoteService.softDelete(notes.last!)
        NoteService.undoDelete(notes.last!)
        NoteService.setFolder(folders[0], for: notes[1])
        _ = NoteService.add(title: "нова", folder: nil, in: context)

        snapshot = try fetchAll(context)
        let slice = model.slice(all: snapshot)
        let reference = NoteListSliceEngine.computeReference(
            all: snapshot, folderID: nil)
        XCTAssertTrue(slice.items.elementsEqual(reference.items, by: ===))
        XCTAssertEqual(slice.countAll, reference.countAll)
        XCTAssertEqual(slice.countByFolder, reference.countByFolder)
    }

    /// bulkChanged змушує наступний зріз перечитати базу
    func testBulkChangedInvalidatesModelCache() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 11)
        let folders = [NoteFolder(name: "Ідеї")]
        folders.forEach(context.insert)
        let notes = seed(context, folders: folders, count: 20, rng: &rng)

        let model = NotesModel()
        var snapshot = try fetchAll(context)
        _ = model.slice(all: snapshot)

        // Мутація ПОВЗ NoteMutation.changed — як обслуговування
        let victim = notes.first { $0.deletedAt == nil }!
        victim.deletedAt = .now
        NoteMutation.bulkChanged()

        snapshot = try fetchAll(context)
        let slice = model.slice(all: snapshot)
        XCTAssertFalse(slice.items.contains { $0 === victim })
    }
}
