//
//  NoteUndoAtomicsTests.swift
//  EmbarTests
//
//  Сторож ⌘Z у тілі нотатки (блокер тест-плану 2026-08-25).
//
//  Дві половини блокера:
//  · Делегат розширював правку, що частково зачепила атом (чіп-згадку,
//    блок цитати Рідера), ВЛАСНОЮ заміною зсередини shouldChangeTextIn і
//    вертав false зовнішньому виклику — проти контракту пари
//    shouldChangeText → didChangeText, в якій NSTextView веде облік undo.
//    Тепер розширення живе ДО пари (snapDeletionToAtom у EmbarTextView +
//    снап виділення), а делегат лише відмовляє екзотичним частковим
//    правкам, нічого не змінюючи.
//  · ToastCenter.UndoAction був класом: його ізольований deinit у
//    back-deploy рантаймі псував купу при звільненні всередині Task
//    (ASan: free on address which was not malloc()-ed; той самий підпис —
//    краші StickyHeightEstimator 2026-08-18). Тепер це структура. Тести
//    фото-ряду ловлять регрес разом з ASan-прогоном (⌘U з Address
//    Sanitizer або xcodebuild -enableAddressSanitizer YES).
//
//  Харнес: у тестовому тілі немає подій, тож неявна undo-група
//  groupsByEvent НЕ закривається сама — один undo() відкочував би всю
//  сесію (перша версія проби саме так збрехала про «стертий документ»).
//  А ручне endUndoGrouping поверх неявної групи лишає менеджер у стані
//  «реєструвати не можна». Тому КОЖНА логічна дія йде через op {} —
//  явну пару begin/endUndoGrouping: рівно та сама гранулярність «одна
//  подія — одна група», що в живому застосунку.
//

import XCTest
import AppKit
import SwiftData
@testable import Embar

@MainActor
final class NoteUndoAtomicsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var window: NSWindow!
    private var tv: EmbarTextView!
    private var model: NoteEditorModel!
    private var coordinator: NoteBodyView.Coordinator!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            container = try! ModelContainer(
                for: EmbarApp.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = ModelContext(container)
            let note = NoteService.add(title: "Проба", in: context)
            model = NoteEditorModel(note: note, context: context)

            // Точна копія стека з NoteBodyView.makeNSView
            let storage = NSTextStorage()
            let layout = EmbarSelectionLayoutManager()
            let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            tc.widthTracksTextView = true
            storage.addLayoutManager(layout)
            layout.addTextContainer(tc)

            tv = EmbarTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 400),
                               textContainer: tc)
            coordinator = NoteBodyView.Coordinator()
            coordinator.model = model
            tv.delegate = coordinator
            tv.isRichText = true
            tv.allowsUndo = true
            tv.isEditable = true
            tv.drawsBackground = false
            tv.typingAttributes = model.bodyTypingAttributes()
            model.attach(tv)

            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
            // ❗ Інакше close() звільняє вікно, ARC звільняє вдруге —
            // SIGSEGV на зливі autorelease-пулу
            window.isReleasedWhenClosed = false
            window.contentView = tv
            coordinator.loadIfNeeded(into: tv)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            model?.saveNow()
            window?.close()
            window = nil
            tv = nil
            model = nil
            coordinator = nil
            context = nil
            container = nil
        }
        super.tearDown()
    }

    // MARK: - Помічники

    /// Одна «подія»: явна undo-група навколо дії + розрив коалесценції
    /// набору + оберт run loop для Task-ів (тости, дебаунс збереження)
    private func op(_ body: () -> Void) {
        guard let um = tv.undoManager else { return XCTFail("немає undo-менеджера") }
        um.beginUndoGrouping()
        body()
        tv.breakUndoCoalescing()
        um.endUndoGrouping()
        // Перша реєстрація в «події» відкриває ще й НЕЯВНУ подієву групу
        // НАВКОЛО нашої — без подій вона не закриється ніколи, і один
        // undo() зняв би всю сесію. Добиваємо до рівня 0; реєстрації
        // завжди йдуть усередині явної групи, тож стан лишається легальним
        while um.groupingLevel > 0 { um.endUndoGrouping() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    /// Набір «як з клавіатури»: посимвольно через insertText → делегат
    private func type(_ s: String) {
        for ch in s {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
        }
    }

    private func undo() { tv.undoManager?.undo() }
    private func redo() { tv.undoManager?.redo() }

    /// Вставити чіп-згадку тим самим шляхом, що insertMention у моделі
    private func insertChip(title: String) {
        var base = tv.typingAttributes
        base[.embarMention] = nil
        var chip = base
        chip[.embarMention] = UUID().uuidString as NSString
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

    /// Вставити блок цитати Рідера (атомарний ран .embarReaderQuote)
    private func insertReaderQuote(_ text: String) {
        var quote = model.bodyTypingAttributes()
        quote[.embarReaderQuote] = NSNumber(value: true)
        let q = NSAttributedString(string: text, attributes: quote)
        let r = tv.selectedRange()
        guard tv.shouldChangeText(in: r, replacementString: q.string) else {
            return XCTFail("вставку цитати відхилено")
        }
        tv.textStorage!.replaceCharacters(in: r, with: q)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: r.location + q.length, length: 0))
    }

    /// Вставити фото-ряд (attachment) тим самим шляхом, що finishPhotoRowInsert
    private func insertPhotoRow() {
        let att = EmbarPhotoRowAttachment(imageIDs: [UUID().uuidString], columns: 1)
        var photoAttrs = model.bodyTypingAttributes()
        photoAttrs[.paragraphStyle] = NoteTypography.photoRowParagraphStyle()
        let block = NSMutableAttributedString(attachment: att)
        block.addAttributes(photoAttrs, range: NSRange(location: 0, length: block.length))
        block.append(NSAttributedString(string: "\n", attributes: photoAttrs))
        let r = tv.selectedRange()
        guard tv.shouldChangeText(in: r, replacementString: block.string) else {
            return XCTFail("вставку фото-ряду відхилено")
        }
        tv.textStorage!.replaceCharacters(in: r, with: block)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: r.location + block.length, length: 0))
    }

    /// Ран першого атома, що містить `needle` (для позиціювання каретки)
    private func atomRun(containing needle: String) -> NSRange? {
        let idx = (tv.string as NSString).range(of: needle).location
        guard idx != NSNotFound else { return nil }
        return tv.atomicRun(at: idx)
    }

    private var photoCharIndex: Int? {
        let i = (tv.string as NSString).range(of: "\u{FFFC}").location
        return i == NSNotFound ? nil : i
    }

    // MARK: - База

    func testPlainTypingUndoRedo() {
        XCTAssertNotNil(tv.undoManager, "без undo-менеджера решта тестів нічого не перевіряє")
        op { type("привіт світ") }
        undo()
        XCTAssertEqual(tv.string, "", "набір відкочується")
        redo()
        XCTAssertEqual(tv.string, "привіт світ")
    }

    func testUndoOnEmptyStackIsHarmless() {
        undo()
        undo()
        XCTAssertEqual(tv.string, "")
    }

    func testTwoTypingBurstsAreSeparateUndoSteps() {
        op { type("перший ") }
        op { type("другий") }
        undo()
        XCTAssertEqual(tv.string, "перший ", "один ⌘Z знімає одну «подію», не всю сесію")
        undo()
        XCTAssertEqual(tv.string, "")
    }

    func testBoldToggleThenUndo() {
        op { type("жирний шматок") }
        op {
            tv.setSelectedRange(NSRange(location: 0, length: 6))
            model.toggleBold()
        }
        undo()
        undo()
        XCTAssertEqual(tv.string, "")
    }

    // MARK: - Чіп-згадка

    /// Backspace одразу за чіпом зносить чіп ЦІЛКОМ (snapDeletionToAtom),
    /// а ⌘Z повертає текст, не порожній документ (регрес блокера)
    func testBackspaceAfterChipDeletesWholeChipAndUndoRestores() throws {
        op { type("до ") }
        op { insertChip(title: "Згадана") }
        op { type("після") }
        let full = tv.string
        let run = try XCTUnwrap(atomRun(containing: "Згадана"))
        op {
            tv.setSelectedRange(NSRange(location: run.location + run.length, length: 0))
            tv.deleteBackward(nil)
        }
        XCTAssertFalse(tv.string.contains("Згадана"), "чіп зноситься цілком")
        XCTAssertTrue(tv.string.contains("до "), "решта тексту недоторкана")
        undo()
        XCTAssertEqual(tv.string, full, "⌘Z повертає чіп і текст")
        redo()
        XCTAssertFalse(tv.string.contains("Згадана"))
        undo()
        XCTAssertEqual(tv.string, full, "гойдалка undo/redo стабільна")
    }

    /// ⌥Backspace (delete word) за чіпом — той самий снап на весь атом
    func testWordDeleteAfterChipDeletesWholeChipAndUndoRestores() throws {
        op { insertChip(title: "Ціль") }
        let full = tv.string
        let run = try XCTUnwrap(atomRun(containing: "Ціль"))
        op {
            tv.setSelectedRange(NSRange(location: run.location + run.length, length: 0))
            tv.deleteWordBackward(nil)
        }
        XCTAssertFalse(tv.string.contains("Ціль"))
        undo()
        XCTAssertEqual(tv.string, full)
    }

    /// Частковий діапазон повз клавіатуру (екзотика: спелчекер, сервіси) —
    /// відмова без жодних змін: атом цілий, документ цілий, undo не забруднено
    func testPartialRangeEditIsRejectedAndAtomIntact() throws {
        op { type("до ") }
        op { insertChip(title: "Згадана") }
        let full = tv.string
        let run = try XCTUnwrap(atomRun(containing: "Згадана"))
        // Без op {}: відхилена правка не реєструє нічого в undo, тож і
        // групи їй не треба (op лишив би порожню групу, якої в реальному
        // застосунку не буває — подієва група без реєстрацій зникає сама)
        let partial = NSRange(location: run.location + run.length - 3, length: 4)
        tv.insertText("", replacementRange: partial)
        XCTAssertEqual(tv.string, full, "часткова правка відхилена без сліду")
        undo()
        XCTAssertEqual(tv.string, "до ", "⌘Z відкочує ПОПЕРЕДНІЙ крок (чіп), а не фантом")
    }

    // MARK: - Блок цитати Рідера

    func testBackspaceAfterReaderBlockDeletesWholeBlockAndUndoRestores() throws {
        op { type("до\n") }
        op { insertReaderQuote("цитата з книги") }
        let full = tv.string
        let run = try XCTUnwrap(atomRun(containing: "цитата"))
        op {
            tv.setSelectedRange(NSRange(location: run.location + run.length, length: 0))
            tv.deleteBackward(nil)
        }
        XCTAssertFalse(tv.string.contains("цитата"), "блок зноситься цілком")
        undo()
        XCTAssertEqual(tv.string, full, "⌘Z повертає блок")
    }

    // MARK: - Фото-ряд

    /// Видалення фото-ряду моделлю → ⌘Z повертає attachment; верстка після
    /// повернення форсується. Прогін під ASan тримає і регрес UndoAction
    /// (купа псувалась при звільненні обгортки тоста всередині Task)
    func testPhotoRowDeleteThenUndoRestores() throws {
        op { type("текст\n") }
        op { insertPhotoRow() }
        let full = tv.string
        let idx = try XCTUnwrap(photoCharIndex)
        op { model.deletePhotoRow(at: idx) }
        XCTAssertNil(photoCharIndex, "фото-ряд видалено")
        undo()
        XCTAssertEqual(tv.string, full, "⌘Z повертає фото-ряд")
        _ = tv.layoutManager?.usedRect(for: tv.textContainer!)
        // Тост «Фото видалено» вже висить: дати його обгортці звільнитись
        // усередині Task-а тоста — саме там ловився зіпсований deinit
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - Комбінації: кілька атомів підряд → стільки ж ⌘Z

    func testDeleteChipThenPhotoThenTwoUndosRestoreBoth() throws {
        op { insertChip(title: "Перший") }
        op { type("\n") }
        op { insertPhotoRow() }
        let full = tv.string

        let run = try XCTUnwrap(atomRun(containing: "Перший"))
        op {
            tv.setSelectedRange(NSRange(location: run.location + run.length, length: 0))
            tv.deleteBackward(nil)
        }
        let idx = try XCTUnwrap(photoCharIndex)
        op { model.deletePhotoRow(at: idx) }
        XCTAssertFalse(tv.string.contains("Перший"))
        XCTAssertNil(photoCharIndex)

        undo()
        XCTAssertNotNil(photoCharIndex, "перший ⌘Z повертає останнє видалення (фото)")
        undo()
        XCTAssertEqual(tv.string, full, "другий ⌘Z повертає чіп — документ як був")
    }

    func testDeleteQuoteThenChipThenTwoUndosRestoreBoth() throws {
        op { insertReaderQuote("рядок цитати") }
        op { type("\n") }
        op { insertChip(title: "Другий") }
        let full = tv.string

        let chip = try XCTUnwrap(atomRun(containing: "Другий"))
        op {
            tv.setSelectedRange(NSRange(location: chip.location + chip.length, length: 0))
            tv.deleteBackward(nil)
        }
        let quote = try XCTUnwrap(atomRun(containing: "цитати"))
        op {
            tv.setSelectedRange(NSRange(location: quote.location + quote.length, length: 0))
            tv.deleteBackward(nil)
        }
        XCTAssertFalse(tv.string.contains("Другий"))
        XCTAssertFalse(tv.string.contains("цитати"))

        undo()
        XCTAssertTrue(tv.string.contains("цитати"), "перший ⌘Z повертає цитату")
        undo()
        XCTAssertEqual(tv.string, full, "другий ⌘Z повертає чіп")
    }
}
