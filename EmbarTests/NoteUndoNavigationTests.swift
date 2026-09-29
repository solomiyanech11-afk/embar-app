//
//  NoteUndoNavigationTests.swift
//  EmbarTests
//
//  Сторож блокера «⌘Z після видалення цілі звʼязку» (2026-08-26):
//  A → [[чіп на B → відкрити B → видалити B → назад в A → ⌘Z = вічний
//  спінер. Корінь був НЕ в undo-механіці: NoteEditorModel умирає при
//  кожній навігації, а синтезований ізольований deinit у back-deploy
//  рантаймі псував купу при звільненні всередині Task (див. CLAUDE.md
//  «Ізольований deinit»). Фікс — явний nonisolated deinit + undo-менеджер
//  НА РЕДАКТОР (был один на вікно: операції переживали перемикання і
//  цілили в мертві text view — NSUndoManager цілі не ретейнить).
//
//  Кожна нотатка тут — свіжий стек редактора в одному вікні, рівно як
//  .id(note.id) у ContentView поверх однієї панелі.
//

import XCTest
import AppKit
import SwiftData
@testable import Embar

@MainActor
final class NoteUndoNavigationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var window: NSWindow!

    private struct EditorStack {
        let tv: EmbarTextView
        let model: NoteEditorModel
        let coordinator: NoteBodyView.Coordinator
    }
    private var current: EditorStack?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            container = try! ModelContainer(
                for: EmbarApp.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = ModelContext(container)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            current?.model.saveNow()
            current = nil
            window?.close()
            window = nil
            context = nil
            container = nil
        }
        super.tearDown()
    }

    // MARK: - Помічники (стек редактора як у NoteBodyView.makeNSView)

    @discardableResult
    private func mount(_ note: Note) -> EditorStack {
        let storage = NSTextStorage()
        let layout = EmbarSelectionLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(tc)

        let tv = EmbarTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 400),
                               textContainer: tc)
        let model = NoteEditorModel(note: note, context: context)
        let coordinator = NoteBodyView.Coordinator()
        coordinator.model = model
        tv.delegate = coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.typingAttributes = model.bodyTypingAttributes()
        model.attach(tv)
        window.contentView = tv
        coordinator.loadIfNeeded(into: tv)

        let stack = EditorStack(tv: tv, model: model, coordinator: coordinator)
        current = stack
        return stack
    }

    /// «Піти з нотатки»: збереження (як openMention/close) і повне
    /// звільнення стека. До фіксу СAME цей крок і псував купу —
    /// NoteEditorModel звільняється всередині Task-контексту тесту
    private func unmount() {
        current?.model.saveNow()
        window.contentView = NSView()
        current = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    private func op(_ tv: EmbarTextView, _ body: () -> Void) {
        guard let um = tv.undoManager else { return XCTFail("немає undo-менеджера") }
        um.beginUndoGrouping()
        body()
        tv.breakUndoCoalescing()
        um.endUndoGrouping()
        while um.groupingLevel > 0 { um.endUndoGrouping() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    private func type(_ s: String, into tv: EmbarTextView) {
        for ch in s {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
        }
    }

    private func insertChip(to target: Note, into tv: EmbarTextView) {
        var base = tv.typingAttributes
        base[.embarMention] = nil
        var chip = base
        chip[.embarMention] = target.id.uuidString as NSString
        let title = target.title.isEmpty ? "Без назви" : target.title
        let out = NSMutableAttributedString(string: title, attributes: chip)
        out.append(NSAttributedString(string: "\u{00A0}", attributes: base))
        let r = tv.selectedRange()
        guard tv.shouldChangeText(in: r, replacementString: out.string) else {
            return XCTFail("chip insert відхилено")
        }
        tv.textStorage!.replaceCharacters(in: r, with: out)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: r.location + out.length, length: 0))
    }

    // MARK: - Канарка міни ізольованого deinit

    /// Звільнення NoteEditorModel усередині Task — до фіксу тут падало
    /// «pointer being freed was not allocated» (три краші 2026-08-26)
    func testEditorModelDeinitInsideTaskIsSafe() async {
        let note = NoteService.add(title: "Канарка", in: context)
        let ctx = context!
        await Task { @MainActor in
            _ = NoteEditorModel(note: note, context: ctx)
        }.value
    }

    // MARK: - Репро блокера (2026-08-26)

    /// A: текст + чіп на B → відкрити B → видалити B → назад в A → ⌘Z.
    /// Не висне, не мутує документ і не псує архів
    func testChipToDeletedNoteThenUndoAfterReturn() {
        let noteA = NoteService.add(title: "A", in: context)
        let noteB = NoteService.add(title: "B", in: context)

        let a1 = mount(noteA)
        op(a1.tv) { type("звʼязок: ", into: a1.tv) }
        op(a1.tv) { insertChip(to: noteB, into: a1.tv) }
        let contentA = a1.tv.string
        unmount()                    // openMention: saveNow + push
        mount(noteB)
        unmount()                    // deleteNote: saveNow + back
        NoteService.softDelete(noteB)

        let a2 = mount(noteA)
        XCTAssertEqual(a2.tv.string, contentA, "документ A повернувся з архіву")

        a2.tv.undoManager?.undo()    // тут був вічний спінер

        XCTAssertEqual(a2.tv.string, contentA,
                       "⌘Z у свіжому редакторі не міняє видимий документ A")
        a2.model.saveNow()
        let stored = NoteArchiver.decode(noteA.contentData ?? Data())?.string ?? noteA.content
        XCTAssertEqual(stored, contentA, "архів A не зіпсовано")
        NoteService.undoDelete(noteB)
    }

    /// Сусід: повернення в A БЕЗ видалення B
    func testUndoAfterReturnWithoutDeletion() {
        let noteA = NoteService.add(title: "A", in: context)
        let noteB = NoteService.add(title: "B", in: context)
        let a1 = mount(noteA)
        op(a1.tv) { type("текст A", into: a1.tv) }
        op(a1.tv) { insertChip(to: noteB, into: a1.tv) }
        let contentA = a1.tv.string
        unmount()
        mount(noteB)
        unmount()
        let a2 = mount(noteA)
        a2.tv.undoManager?.undo()
        XCTAssertEqual(a2.tv.string, contentA)
    }

    /// Сусід: ціль видалена і ВІДНОВЛЕНА (undo-тост) до повернення в A
    func testUndoAfterTargetDeletedAndRestored() {
        let noteA = NoteService.add(title: "A", in: context)
        let noteB = NoteService.add(title: "B", in: context)
        let a1 = mount(noteA)
        op(a1.tv) { insertChip(to: noteB, into: a1.tv) }
        let contentA = a1.tv.string
        unmount()
        mount(noteB)
        unmount()
        NoteService.softDelete(noteB)
        NoteService.undoDelete(noteB)  // «Повернути» з тоста
        let a2 = mount(noteA)
        a2.tv.undoManager?.undo()
        XCTAssertEqual(a2.tv.string, contentA)
    }

    // MARK: - Життєвий цикл undo-стеку (питання 3 розслідування)

    /// Undo-менеджер — власність РЕДАКТОРА: операції не течуть у менеджер
    /// вікна і не переживають перемикання нотаток
    func testUndoStackIsScopedToEditor() {
        let noteA = NoteService.add(title: "A", in: context)
        let noteB = NoteService.add(title: "B", in: context)

        let a1 = mount(noteA)
        XCTAssertTrue(a1.tv.undoManager === a1.coordinator.editorUndoManager,
                      "text view бере менеджер редактора, не вікна")
        op(a1.tv) { type("щось", into: a1.tv) }
        XCTAssertTrue(a1.tv.undoManager?.canUndo == true)
        XCTAssertFalse(window.undoManager?.canUndo == true,
                       "операції редактора не течуть у менеджер вікна")
        unmount()

        let b = mount(noteB)
        XCTAssertFalse(b.tv.undoManager?.canUndo == true,
                       "стек нотатки A не переживає перехід у B")
        b.tv.undoManager?.undo() // порожній стек — тихий no-op
        XCTAssertEqual(b.tv.string, "")
    }
}
