//
//  NoteListQuoteRulesTests.swift
//  EmbarTests
//
//  R1 (логіка списків) + R2 (логіка блоку цитати) редактора нотаток
//  (TEST-FINDINGS P3). Перевірки на рівні атрибутів тексту: справжній
//  стек EmbarTextView + Coordinator + вікно — той самий харнес, що в
//  NoteUndoAtomicsTests (там і пояснення, чому кожна логічна дія
//  загортається в op {} — явну undo-групу «одна подія — один ⌘Z»).
//

import XCTest
import AppKit
import SwiftData
@testable import Embar

@MainActor
final class NoteListQuoteRulesTests: XCTestCase {

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

    // MARK: - Помічники (див. NoteUndoAtomicsTests: op = одна «подія»)

    private func op(_ body: () -> Void) {
        guard let um = tv.undoManager else { return XCTFail("немає undo-менеджера") }
        um.beginUndoGrouping()
        body()
        tv.breakUndoCoalescing()
        um.endUndoGrouping()
        while um.groupingLevel > 0 { um.endUndoGrouping() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    private func type(_ s: String) {
        for ch in s {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
        }
    }

    private func undo() { tv.undoManager?.undo() }
    private func redo() { tv.undoManager?.redo() }

    private func caret(_ loc: Int) { tv.setSelectedRange(NSRange(location: loc, length: 0)) }

    /// Атрибути на початку абзацу, в якому лежить `index`
    private func paraAttrs(at index: Int) -> [NSAttributedString.Key: Any] {
        let storage = tv.textStorage!
        let pr = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: min(index, storage.length), length: 0))
        guard pr.length > 0, pr.location < storage.length else { return [:] }
        return storage.attributes(at: pr.location, effectiveRange: nil)
    }

    private func listStyle(at index: Int) -> String? {
        paraAttrs(at: index)[.embarList] as? String
    }

    private func isQuote(at index: Int) -> Bool {
        (paraAttrs(at: index)[.embarQuote] as? NSNumber)?.boolValue ?? false
    }

    private func headIndent(at index: Int) -> CGFloat {
        (paraAttrs(at: index)[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0
    }

    /// Позиція початку тексту пункту (одразу після «гліф⇥»)
    private func contentStart(ofParagraphAt index: Int) -> Int {
        let s = tv.string as NSString
        let pr = s.paragraphRange(for: NSRange(location: index, length: 0))
        let tab = s.range(of: "\t", options: [], range: pr)
        return tab.location == NSNotFound ? pr.location : tab.location + tab.length
    }

    // MARK: - L1: Enter на пункті з текстом → новий пункт, той самий маркер

    func testEnterContinuesListForEveryStyle() {
        let expected: [(ListStyle, String)] = [
            (.bullet, "•"), (.number, "2."), (.arrow, "→"), (.triangle, "▸"),
        ]
        for (style, marker) in expected {
            op { model.toggleList(style) }
            op { type("перший") }
            op { tv.insertNewline(nil) }
            XCTAssertEqual(listStyle(at: tv.selectedRange().location), style.rawValue,
                           "\(style): новий рядок лишається пунктом")
            let line = (tv.string as NSString)
                .paragraphRange(for: NSRange(location: tv.selectedRange().location, length: 0))
            XCTAssertTrue((tv.string as NSString).substring(with: line).hasPrefix("\(marker)\t"),
                          "\(style): маркер другого пункту — «\(marker)»")
            // Очистити документ для наступного стилю
            op {
                tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage!.length))
                tv.delete(nil)
                tv.typingAttributes = model.bodyTypingAttributes()
            }
        }
    }

    // MARK: - L2: Enter на порожньому пункті → вихід зі списку, 1 ⌘Z повертає

    func testEnterOnEmptyItemExitsListAndUndoRestores() {
        op { model.toggleList(.bullet) }
        op { type("пункт") }
        op { tv.insertNewline(nil) }          // другий пункт (порожній)
        let before = tv.string
        op { tv.insertNewline(nil) }          // порожній пункт → вихід
        let sel = tv.selectedRange()
        XCTAssertNil(listStyle(at: sel.location), "атрибут списку знято")
        XCTAssertFalse(tv.string.hasSuffix("•\t"), "маркер зник")
        XCTAssertNil(tv.typingAttributes[.embarList], "typing-атрибути без списку")
        XCTAssertEqual(headIndent(at: sel.location), 0, "відступ знято")
        undo()
        XCTAssertEqual(tv.string, before, "один ⌘Z повертає порожній пункт")
        redo()
        XCTAssertFalse(tv.string.hasSuffix("•\t"), "redo стабільний")
    }

    // MARK: - L12: каретка не стоїть у зоні маркера

    func testCaretSnapsOutOfMarkerZone() {
        op { type("нульовий") }
        op { tv.insertNewline(nil) }
        op { model.toggleList(.bullet) }
        op { type("пункт") }
        let s = tv.string as NSString
        let itemPr = s.paragraphRange(for: NSRange(location: s.length - 1, length: 0))
        let content = contentStart(ofParagraphAt: itemPr.location)
        XCTAssertGreaterThan(content, itemPr.location, "маркер існує")

        // Спроба поставити каретку перед маркером і всередину «•|⇥»
        caret(itemPr.location)
        XCTAssertEqual(tv.selectedRange().location, content, "початок абзацу → початок тексту")
        caret(0) // стрибок здалеку (не з межі маркера) — як клік/↑↓
        caret(itemPr.location + 1)
        XCTAssertEqual(tv.selectedRange().location, content, "між гліфом і табом → початок тексту")

        // ← з початку тексту перескакує маркер на кінець попереднього рядка
        caret(content)
        tv.moveLeft(nil)
        XCTAssertEqual(tv.selectedRange().location, itemPr.location - 1,
                       "← перестрибує маркер на кінець попереднього рядка")
        // → назад: перша ж позиція в зоні маркера виштовхує на початок тексту
        tv.moveRight(nil)
        XCTAssertEqual(tv.selectedRange().location, content, "→ повертає на початок тексту")
        // Стрілки не застрягають: ще раз → рухає далі по тексту
        tv.moveRight(nil)
        XCTAssertEqual(tv.selectedRange().location, content + 1)
    }

    func testCaretSnapInFirstParagraphListDoesNotUnderflow() {
        op { model.toggleList(.bullet) }
        op { type("перший") }
        let content = contentStart(ofParagraphAt: 0)
        caret(content)
        tv.moveLeft(nil) // зона на початку документа: ліворуч нема куди
        XCTAssertEqual(tv.selectedRange().location, content, "каретка лишається на початку тексту")
    }

    // MARK: - L3: після виходу зі списку набір — звичайний текст

    func testTypingAfterListExitHasNoPhantomIndent() {
        op { model.toggleList(.bullet) }
        op { type("пункт") }
        op { tv.insertNewline(nil) }
        op { tv.insertNewline(nil) } // порожній пункт → вихід
        op { type("звичайний") }
        let loc = tv.selectedRange().location
        XCTAssertNil(listStyle(at: loc), "абзац без .embarList")
        XCTAssertEqual(headIndent(at: loc), 0, "без спискового відступу")
        XCTAssertNil(tv.typingAttributes[.embarList])
    }

    // MARK: - L4: фантомний .embarList без маркера не продовжує список

    func testPhantomListAttributeWithoutMarkerIsCleanedOnEnter() {
        op { type("текст без маркера") }
        // Фантом: атрибут списку без гліфа в тексті (так виглядає абзац
        // після злиття рядків або фрагмент, вирізаний зсередини пункту)
        let storage = tv.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        op {
            _ = tv.shouldChangeText(in: full, replacementString: nil)
            storage.addAttribute(.embarList, value: ListStyle.bullet.rawValue as NSString, range: full)
            tv.didChangeText()
        }
        caret(storage.length)
        op { tv.insertNewline(nil) }
        XCTAssertFalse(tv.string.contains("•"), "жодного фантомного маркера")
        XCTAssertNil(listStyle(at: 0), "атрибут зачищено з абзацу")
        XCTAssertNil(tv.typingAttributes[.embarList])
    }

    // MARK: - L5: тогл-вимк. знімає все з усього абзацу, вирівнювання живе

    func testToggleOffClearsWholeParagraphAndKeepsAlignment() {
        op { type("центрований пункт") }
        op { model.setAlignment(.center) }
        op { model.toggleList(.bullet) }
        let withList = tv.string
        XCTAssertTrue(withList.hasPrefix("•\t"))
        op { model.toggleList(.bullet) } // зняти
        XCTAssertEqual(tv.string, "центрований пункт", "маркер зник")
        let storage = tv.textStorage!
        storage.enumerateAttribute(.embarList, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            XCTAssertNil(v, "\(r): .embarList знято з УСЬОГО абзацу")
        }
        XCTAssertEqual(headIndent(at: 0), 0, "відступ знято")
        let align = (paraAttrs(at: 0)[.paragraphStyle] as? NSParagraphStyle)?.alignment
        XCTAssertEqual(align, .center, "вирівнювання пережило тогл")
        undo()
        XCTAssertEqual(tv.string, withList, "один ⌘Z повертає список")
        XCTAssertEqual(listStyle(at: 0), ListStyle.bullet.rawValue)
        redo()
        XCTAssertEqual(tv.string, "центрований пункт", "redo стабільний")
    }

    // MARK: - L6: тогл по виділенню кількох пунктів (з порожнім усередині)

    func testToggleOffAcrossSelectionWithEmptyParagraph() {
        op { type("а\n\nб") } // три абзаци, середній порожній
        op {
            tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage!.length))
            model.toggleList(.bullet)
        }
        XCTAssertEqual(tv.string, "•\tа\n•\t\n•\tб", "маркери на всіх, включно з порожнім")
        let listed = tv.string
        op {
            tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage!.length))
            model.toggleList(.bullet)
        }
        XCTAssertEqual(tv.string, "а\n\nб", "усі чисті одним топлом")
        let storage = tv.textStorage!
        storage.enumerateAttribute(.embarList, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            XCTAssertNil(v, "\(r): без залишків атрибута")
        }
        undo()
        XCTAssertEqual(tv.string, listed, "один ⌘Z повертає всі маркери")
    }

    // MARK: - L7: перемикання стилю маркера на місці

    func testSwitchingMarkerStyleReplacesInPlace() {
        op { type("один") }
        op { model.toggleList(.number) }
        op { tv.insertNewline(nil) }
        op { type("два") }
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tдва")
        op {
            tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage!.length))
            model.toggleList(.bullet)
        }
        XCTAssertEqual(tv.string, "•\tодин\n•\tдва", "номери → крапки")
        op {
            tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage!.length))
            model.toggleList(.number)
        }
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tдва", "назад — перелічено заново")
    }

    // MARK: - L8: список поверх цитати знімає цитату (без гібрида)

    func testListOnQuoteParagraphClearsQuote() {
        op { model.toggleQuote() }
        op { type("була цитата") }
        XCTAssertTrue(isQuote(at: 0))
        op { model.toggleList(.bullet) }
        XCTAssertEqual(listStyle(at: 0), ListStyle.bullet.rawValue)
        XCTAssertFalse(isQuote(at: 0), ".embarQuote знято — список і цитата взаємовиключні")
        let font = paraAttrs(at: contentStart(ofParagraphAt: 0))[.font] as? NSFont
        XCTAssertNotEqual(font?.fontName, NoteTypography.quoteFont().fontName, "шрифт цитати перевиведено")
    }

    // MARK: - L9: Backspace на початку тексту пункту — розформатувати, не злити

    func testBackspaceAtItemContentStartUnlistsAndRenumbers() {
        op { type("один") }
        op { model.toggleList(.number) }
        op { tv.insertNewline(nil) }
        op { type("два") }
        op { tv.insertNewline(nil) }
        op { type("три") }
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tдва\n3.\tтри")
        let before = tv.string

        // Каретка на початок тексту другого пункту
        let second = (tv.string as NSString).range(of: "два").location
        caret(second)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, "1.\tодин\nдва\n1.\tтри",
                       "маркер знято, текст лишився; третій пункт — новий блок з 1.")
        let plainLoc = (tv.string as NSString).range(of: "два").location
        XCTAssertNil(listStyle(at: plainLoc), "атрибут списку знято")
        XCTAssertEqual(headIndent(at: plainLoc), 0)
        XCTAssertEqual(tv.selectedRange().location, plainLoc, "каретка на початку тексту")

        undo()
        XCTAssertEqual(tv.string, before, "один ⌘Z повертає пункт і номери")
        XCTAssertEqual(listStyle(at: second), ListStyle.number.rawValue)
        redo()
        XCTAssertEqual(tv.string, "1.\tодин\nдва\n1.\tтри", "redo стабільний")
        undo()
        XCTAssertEqual(tv.string, before, "гойдалка undo/redo стабільна")
    }

    func testWordBackspaceAtItemContentStartUnlistsToo() {
        op { model.toggleList(.bullet) }
        op { type("пункт") }
        caret(contentStart(ofParagraphAt: 0))
        op { tv.deleteWordBackward(nil) }
        XCTAssertEqual(tv.string, "пункт", "⌥⌫ — те саме правило, що ⌫")
        XCTAssertNil(listStyle(at: 0))
    }

    // MARK: - Q1/Q2: Backspace на початку цитати — зняти формат, не злити

    func testBackspaceAtQuoteStartUnquotesWithoutMerge() {
        op { type("верх") }
        op { tv.insertNewline(nil) }
        op { model.toggleQuote() }
        op { type("цитата") }
        let qLoc = (tv.string as NSString).range(of: "цитата").location
        XCTAssertTrue(isQuote(at: qLoc))
        let before = tv.string

        caret(qLoc)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, before, "рядки НЕ злиті — знято лише формат")
        XCTAssertFalse(isQuote(at: qLoc), ".embarQuote знято")
        XCTAssertEqual(headIndent(at: qLoc), 0, "відступ цитати знято")
        let font = paraAttrs(at: qLoc)[.font] as? NSFont
        XCTAssertNotEqual(font?.fontName, NoteTypography.quoteFont().fontName, "шрифт перевиведено")

        undo()
        XCTAssertTrue(isQuote(at: qLoc), "один ⌘Z повертає цитату")
        redo()
        XCTAssertFalse(isQuote(at: qLoc), "redo стабільний")

        // Q2: другий Backspace — звичайне злиття (redo відновив виділення
        // на весь абзац — каретку явно на початок тексту)
        caret(qLoc)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, "верхцитата", "другий ⌫ зливає рядки")
        XCTAssertFalse(isQuote(at: 0))
    }

    // MARK: - Q3/Q4: злиття рядка назад у цитату повертає їй формат

    func testBackspaceMergeIntoQuoteRestoresQuoteFormat() {
        op { model.toggleQuote() }
        op { type("цитата") }
        op { tv.insertNewline(nil) } // Enter у цитаті → хвіст звичайний (Q4, працює)
        op { type("хвіст") }
        let tailLoc = (tv.string as NSString).range(of: "хвіст").location
        XCTAssertFalse(isQuote(at: tailLoc), "новий рядок після Enter — звичайний")
        let split = tv.string

        caret(tailLoc)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, "цитатахвіст", "рядки злиті")
        XCTAssertTrue(isQuote(at: 0), "абзац лишився цитатою")
        let storage = tv.textStorage!
        let tail = (tv.string as NSString).range(of: "хвіст")
        let tailAttrs = storage.attributes(at: tail.location, effectiveRange: nil)
        XCTAssertTrue((tailAttrs[.embarQuote] as? NSNumber)?.boolValue ?? false,
                      "влитий текст набув формату цитати")
        XCTAssertEqual((tailAttrs[.font] as? NSFont)?.fontName,
                       NoteTypography.quoteFont().fontName, "влитий текст — шрифтом цитати")

        undo()
        XCTAssertEqual(tv.string, split, "один ⌘Z повертає розділені рядки")
        XCTAssertFalse(isQuote(at: tailLoc), "хвіст після undo знову звичайний")
        redo()
        XCTAssertEqual(tv.string, "цитатахвіст", "redo стабільний")
    }

    // MARK: - Q5: deleteForward у кінці цитати втягує рядок у цитату

    func testForwardDeleteAtQuoteEndPullsNextLineIntoQuote() {
        op { model.toggleQuote() }
        op { type("цитата") }
        op { tv.insertNewline(nil) }
        op { type("низ") }
        let qEnd = (tv.string as NSString).range(of: "цитата").location + "цитата".count
        caret(qEnd)
        op { tv.deleteForward(nil) }
        XCTAssertEqual(tv.string, "цитатаниз")
        let tail = (tv.string as NSString).range(of: "низ")
        let tailAttrs = tv.textStorage!.attributes(at: tail.location, effectiveRange: nil)
        XCTAssertTrue((tailAttrs[.embarQuote] as? NSNumber)?.boolValue ?? false,
                      "втягнутий рядок став цитатою")
    }

    // MARK: - Q10: ⌥⌫ на початку цитати — те саме правило

    func testWordBackspaceAtQuoteStartUnquotesToo() {
        op { type("верх") }
        op { tv.insertNewline(nil) }
        op { model.toggleQuote() }
        op { type("цитата") }
        let qLoc = (tv.string as NSString).range(of: "цитата").location
        caret(qLoc)
        op { tv.deleteWordBackward(nil) }
        XCTAssertEqual(tv.string, "верх\nцитата", "без злиття")
        XCTAssertFalse(isQuote(at: qLoc), "формат знято")
    }

    // MARK: - L10: злиття рядка в пункт списку — текст стає пунктом

    func testBackspaceMergeIntoListItemAdoptsListFormat() {
        op { type("один") }
        op { model.toggleList(.number) }
        op { tv.insertNewline(nil) }
        op { type("два") }
        // Вивести другий рядок зі списку (⌫ на початку тексту), лишивши текст
        let second = (tv.string as NSString).range(of: "два").location
        caret(second)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, "1.\tодин\nдва")
        // Тепер злити його назад у пункт
        caret((tv.string as NSString).range(of: "два").location)
        op { tv.deleteBackward(nil) }
        XCTAssertEqual(tv.string, "1.\tодиндва", "злито в пункт")
        let tail = (tv.string as NSString).range(of: "два")
        let tailAttrs = tv.textStorage!.attributes(at: tail.location, effectiveRange: nil)
        XCTAssertEqual(tailAttrs[.embarList] as? String, ListStyle.number.rawValue,
                       "влитий текст набув атрибутів пункту")
        XCTAssertFalse(tv.string.contains("2."), "гліфів-сиріт нема")
    }

    // MARK: - L11: видалення цілого пункту перенумеровує решту

    func testDeletingWholeItemRenumbersFollowing() {
        op { type("один") }
        op { model.toggleList(.number) }
        op { tv.insertNewline(nil) }
        op { type("два") }
        op { tv.insertNewline(nil) }
        op { type("три") }
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tдва\n3.\tтри")
        let s = tv.string as NSString
        let item2 = s.paragraphRange(for: NSRange(location: s.range(of: "два").location, length: 0))
        op {
            tv.setSelectedRange(item2)
            tv.deleteBackward(nil)
        }
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tтри", "пункт зник, номери перелічені")
        undo()
        XCTAssertEqual(tv.string, "1.\tодин\n2.\tдва\n3.\tтри", "один ⌘Z повертає пункт і номери")
    }

    // MARK: - Хвіст цитати/пункту, влитий у звичайну голову, не лишає фантомів

    func testMergeIntoPlainHeadStripsSpecialResidue() {
        op { type("голова") }
        op { tv.insertNewline(nil) }
        op { model.toggleQuote() }
        op { type("цитата") }
        // Виділення від середини голови до середини цитати → delete
        let start = 3
        let end = (tv.string as NSString).range(of: "цитата").location + 3
        op {
            tv.setSelectedRange(NSRange(location: start, length: end - start))
            tv.deleteBackward(nil)
        }
        XCTAssertEqual(tv.string, "голата", "злито")
        let storage = tv.textStorage!
        storage.enumerateAttribute(.embarQuote, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            XCTAssertNil(v, "\(r): без залишків .embarQuote у звичайній голові")
        }
        XCTAssertEqual(headIndent(at: 0), 0)
    }

    // MARK: - Q6/Q7: вставка всередину цитати набуває її стилю

    /// Вставити фрагмент дроп-шляхом (readSelection нашого типу) — та сама
    /// воронка, що ⌘V нашого фрагмента, але без чіпання загального пейстборда
    private func dropFragment(_ fragment: NSAttributedString) {
        let pb = NSPasteboard(name: NSPasteboard.Name("EmbarTestQuotePaste"))
        pb.clearContents()
        pb.setData(NoteArchiver.encode(fragment)!, forType: PasteNormalizer.internalType)
        XCTAssertTrue(tv.readSelection(from: pb, type: PasteNormalizer.internalType))
    }

    func testInsertPlainTextInsideQuoteAdoptsQuoteStyle() {
        op { model.toggleQuote() }
        op { type("початок кінець") }
        let before = tv.string
        let mid = (tv.string as NSString).range(of: " кінець").location
        caret(mid)
        let plain = NSAttributedString(string: "середина",
                                       attributes: NoteFormatter.plainTypingAttributes(settings: .default))
        op { dropFragment(plain) }
        XCTAssertEqual(tv.string, "початоксередина кінець")
        let ins = (tv.string as NSString).range(of: "середина")
        let attrs = tv.textStorage!.attributes(at: ins.location, effectiveRange: nil)
        XCTAssertTrue((attrs[.embarQuote] as? NSNumber)?.boolValue ?? false,
                      "вставлене — цитата")
        XCTAssertEqual((attrs[.font] as? NSFont)?.fontName,
                       NoteTypography.quoteFont().fontName, "вставлене — шрифтом цитати")
        undo()
        XCTAssertEqual(tv.string, before, "один ⌘Z знімає всю вставку")
    }

    func testInsertMultiParagraphInsideQuoteAllBecomeQuote() {
        op { model.toggleQuote() }
        op { type("цитата") }
        caret((tv.string as NSString).range(of: "цитата").location + 3)
        let three = NSAttributedString(string: "один\nдва\nтри",
                                       attributes: NoteFormatter.plainTypingAttributes(settings: .default))
        op { dropFragment(three) }
        let storage = tv.textStorage!
        var nonQuote = 0
        storage.enumerateAttribute(.embarQuote, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            if (v as? NSNumber)?.boolValue != true { nonQuote += r.length }
        }
        XCTAssertEqual(nonQuote, 0, "усі вставлені абзаци стали цитатою (рішення Mia)")
    }

    // MARK: - Q8: фрагмент зі списком у цитату — маркери зняті, текст цитата

    func testInsertListFragmentInsideQuoteStripsMarkers() {
        let item = NSMutableAttributedString(
            string: NoteFormatter.markerText(.bullet, index: 1) + "пункт",
            attributes: NoteFormatter.markerAttrs(.p, .bullet, settings: .default))
        op { model.toggleQuote() }
        op { type("ab") }
        caret(1)
        op { dropFragment(item) }
        XCTAssertEqual(tv.string, "aпунктb", "маркер-гліф знято")
        let ins = (tv.string as NSString).range(of: "пункт")
        let attrs = tv.textStorage!.attributes(at: ins.location, effectiveRange: nil)
        XCTAssertNil(attrs[.embarList], "атрибут списку знято")
        XCTAssertTrue((attrs[.embarQuote] as? NSNumber)?.boolValue ?? false, "текст став цитатою")
    }

    // MARK: - Q9: фото-ряд і блок Рідера в цитату не цитуються (чиста функція)

    func testAdoptQuoteStyleLeavesPhotoAndReaderBlocksIntact() {
        let fragment = NSMutableAttributedString()
        fragment.append(NSAttributedString(string: "текст\n",
                                           attributes: NoteFormatter.plainTypingAttributes(settings: .default)))
        var readerAttrs = NoteFormatter.plainTypingAttributes(settings: .default)
        readerAttrs[.embarReaderQuote] = NSNumber(value: true)
        fragment.append(NSAttributedString(string: "блок рідера\n", attributes: readerAttrs))
        let att = EmbarPhotoRowAttachment(imageIDs: [UUID().uuidString], columns: 1)
        var photoAttrs = NoteFormatter.plainTypingAttributes(settings: .default)
        photoAttrs[.paragraphStyle] = NoteTypography.photoRowParagraphStyle()
        let photo = NSMutableAttributedString(attachment: att)
        photo.addAttributes(photoAttrs, range: NSRange(location: 0, length: photo.length))
        photo.append(NSAttributedString(string: "\n", attributes: photoAttrs))
        fragment.append(photo)

        NoteFormatter.adoptQuoteStyle(fragment, settings: .default)

        let textAttrs = fragment.attributes(at: 0, effectiveRange: nil)
        XCTAssertTrue((textAttrs[.embarQuote] as? NSNumber)?.boolValue ?? false, "текст став цитатою")
        let readerLoc = (fragment.string as NSString).range(of: "блок").location
        let rAttrs = fragment.attributes(at: readerLoc, effectiveRange: nil)
        XCTAssertNil(rAttrs[.embarQuote], "блок Рідера лишився собою")
        let photoLoc = (fragment.string as NSString).range(of: "\u{FFFC}").location
        let pAttrs = fragment.attributes(at: photoLoc, effectiveRange: nil)
        XCTAssertNil(pAttrs[.embarQuote], "фото-ряд лишився собою")
        XCTAssertEqual((pAttrs[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple, 1,
                       "стиль фото-абзацу недоторканний")
    }

    // MARK: - Цитата реагує на міжряддя нотатки (фідбек Mia 05.09)

    func testQuoteLineSpacingFollowsSettings() {
        // Normal — рівно 1.6 (пропорція редизайну не ламається)
        var settings = NoteDocSettings()
        settings.lineHeight = .normal
        let normal = NoteTypography.paragraphStyle(role: .p, quote: true, settings: settings)
        XCTAssertEqual(normal.lineHeightMultiple, 1.6, accuracy: 0.001)
        settings.lineHeight = .tight
        let tight = NoteTypography.paragraphStyle(role: .p, quote: true, settings: settings)
        settings.lineHeight = .loose
        let loose = NoteTypography.paragraphStyle(role: .p, quote: true, settings: settings)
        XCTAssertLessThan(tight.lineHeightMultiple, normal.lineHeightMultiple, "Tight — щільніше")
        XCTAssertGreaterThan(loose.lineHeightMultiple, normal.lineHeightMultiple, "Roomy — просторіше")
    }

    func testRestyleDocumentAppliesLineSpacingToQuoteParagraph() {
        op { model.toggleQuote() }
        op { type("цитата") }
        let before = (paraAttrs(at: 0)[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple ?? 0
        var tight = NoteDocSettings()
        tight.lineHeight = .tight
        op { NoteFormatter.restyleDocument(tv, settings: tight) }
        let after = (paraAttrs(at: 0)[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple ?? 0
        XCTAssertLessThan(after, before, "перемикач міжряддя дістає і абзац цитати")
        XCTAssertTrue(isQuote(at: 0), "цитата лишилась цитатою")
    }

    // MARK: - Q11: порожній рядок цитати + Enter → розчиняється на місці (регрес)

    func testEnterOnEmptyQuoteLineDissolvesInPlace() {
        op { model.toggleQuote() }
        XCTAssertTrue((tv.typingAttributes[.embarQuote] as? NSNumber)?.boolValue ?? false)
        op { tv.insertNewline(nil) } // порожній рядок цитати → розчинити
        XCTAssertEqual(tv.string, "", "нового рядка не додано")
        XCTAssertNil(tv.typingAttributes[.embarQuote], "typing-атрибути звичайні")
    }
}
