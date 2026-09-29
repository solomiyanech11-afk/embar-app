//
//  NoteDragDropTests.swift
//  EmbarTests
//
//  F2 (тест-план 2026-08-25, діагностика 2026-08-28): перетягування ряду
//  фото в нотатці знищувало фото. Дві половини одного кореня:
//
//  · Драг усередині NSTextView - це round-trip через пейстборд:
//    writeSelection на старті, дроп читає назад. Свій lossless-тип ми
//    писали, але ЧИТАННЯ дропу йде НЕ через readablePasteboardTypes
//    (то шлях ⌘V), а через acceptableDragTypes - окремий, зашитий в
//    AppKit список стандартних типів. Наш тип там відсутній, RTFD
//    відкинуто через importsGraphics=false - дроп читав RTF, який
//    викидає attachment-и і всі .embar*-атрибути.
//
//  · Тому перший фікс (лише readSelection) тримав ⌘V і був зелений у
//    тесті, що смикав readSelection напряму, - а руками фото зникали.
//
//  Ці тести йдуть СПРАВЖНІМ шляхом дропу (draggingEntered →
//  draggingUpdated → performDragOperation з NSDraggingInfo) - на коді до
//  фікса вони падають. Покриття - весь корінь: ряд фото, чіп-згадка,
//  хайлайт, роль заголовка, і ⌘Z після дропу.
//

import XCTest
import AppKit
@testable import Embar

/// Мінімальний NSDraggingInfo для headless-дропу (реальну драг-сесію
/// без вікна-сервера не підняти; шлях дропу від draggingEntered і далі -
/// той самий)
private final class FakeDrag: NSObject, NSDraggingInfo {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    let pb: NSPasteboard
    weak var window: NSWindow?
    var source: Any?
    var location: NSPoint
    init(pb: NSPasteboard, window: NSWindow?, source: Any?, location: NSPoint) {
        self.pb = pb; self.window = window; self.source = source; self.location = location
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move, .generic] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var draggingSource: Any? { source }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions,
                                for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

final class NoteDragDropTests: XCTestCase {

    private var window: NSWindow!
    private var coordinator: NoteBodyView.Coordinator!

    override func tearDown() {
        window?.contentView = nil
        window = nil
        coordinator = nil
        super.tearDown()
    }

    /// Вьюха, як її збирає NoteBodyView: наш layout manager, undo через
    /// undo-менеджер РЕДАКТОРА (делегат-координатор - як у застосунку)
    private func makeTextView() -> EmbarTextView {
        let storage = NSTextStorage()
        let layout = EmbarSelectionLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let tv = EmbarTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400),
                               textContainer: container)
        tv.isRichText = true
        tv.isEditable = true
        tv.allowsUndo = true
        tv.importsGraphics = false
        coordinator = NoteBodyView.Coordinator()
        tv.delegate = coordinator
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = tv
        return tv
    }

    /// Справжній шлях жесту Mia: виділити `range`, стартувати драг (запис
    /// на драг-пейстборд), дропнути в `point` (nil = кінець документа).
    /// Повертає false, якщо дроп відхилено
    @discardableResult
    private func drag(_ tv: EmbarTextView, range: NSRange,
                      to point: NSPoint? = nil) -> Bool {
        guard let info = beginDrag(tv, range: range, to: point) else { return false }
        guard tv.draggingEntered(info) != [] else { return false }
        guard tv.draggingUpdated(info) != [] else { return false }
        guard tv.prepareForDragOperation(info) else { return false }
        return tv.performDragOperation(info)
    }

    /// Лише старт драгу і наведення (без дропу) - для перевірок індикатора
    private func beginDrag(_ tv: EmbarTextView, range: NSRange,
                           to point: NSPoint?) -> NSDraggingInfo? {
        guard let storage = tv.textStorage, let layout = tv.layoutManager,
              let container = tv.textContainer else { return nil }
        layout.ensureLayout(for: container)
        tv.setSelectedRange(range)
        let pb = NSPasteboard(name: NSPasteboard.Name("EmbarTestDrag"))
        pb.clearContents()
        // Старт драгу пише РІВНО ці типи (перевірено на живому системному
        // драг-пейстборді 2026-08-28)
        guard tv.writeSelection(to: pb, types: tv.writablePasteboardTypes) else { return nil }
        let dropPoint: NSPoint
        if let point {
            dropPoint = point
        } else {
            let endRect = layout.boundingRect(
                forGlyphRange: NSRange(location: max(storage.length - 1, 0), length: 1),
                in: container)
            dropPoint = NSPoint(x: endRect.maxX + 2, y: endRect.midY)
        }
        return FakeDrag(pb: pb, window: window, source: tv,
                        location: tv.convert(dropPoint, to: nil))
    }

    /// Точка ВСЕРЕДИНІ слова (верхня половина рядка) для символу `index`
    private func midWordPoint(_ tv: EmbarTextView, at index: Int) -> NSPoint {
        let layout = tv.layoutManager!
        let rect = layout.boundingRect(
            forGlyphRange: NSRange(location: index, length: 1), in: tv.textContainer!)
        // minX + 1, не midX: за серединою гліфа системна каретка
        // округлюється до НАСТУПНОГО символу, і «точна позиція» зʼїхала б
        return NSPoint(x: rect.minX + 1 + tv.textContainerOrigin.x,
                       y: rect.minY + 2 + tv.textContainerOrigin.y)
    }

    private func paragraph(attrs: [NSAttributedString.Key: Any] = [:],
                           _ text: String) -> NSAttributedString {
        var a = attrs
        if a[.font] == nil { a[.font] = NoteTypography.font(role: .p) }
        return NSAttributedString(string: text, attributes: a)
    }

    // MARK: - Ряд фото (жест Mia дослівно)

    func testPhotoRowSurvivesRealDrop() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let ids = [UUID().uuidString, UUID().uuidString]
        let doc = NSMutableAttributedString(attachment:
            EmbarPhotoRowAttachment(imageIDs: ids, columns: 2))
        doc.append(paragraph("\nхвіст тексту тут"))
        storage.setAttributedString(doc)

        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 2)), // ￼ + \n
                      "дроп фрагмента з фото відхилено")

        // Вставлена на дропі копія (частина після хвоста) мусить мати наш
        // живий attachment; оригінал у headless-симуляції лишається -
        // його зносить сторона-джерело реальної сесії
        let tailEnd = ("\u{FFFC}\nхвіст тексту тут" as NSString).length
        var dropped: EmbarPhotoRowAttachment?
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: tailEnd, length: storage.length - tailEnd)) { v, _, _ in
            if let a = v as? EmbarPhotoRowAttachment { dropped = a }
        }
        let row = try XCTUnwrap(dropped, "після дропа приїхав не наш attachment - фото втрачені")
        XCTAssertEqual(row.imageIDs, ids)
        XCTAssertEqual(row.columns, 2)
    }

    // MARK: - Той самий корінь: .embar*-атрибути в тексті

    /// Драг тексту з чіпом [[ ]]: згадка лишається чіпом
    func testMentionChipSurvivesRealDrop() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let uuid = UUID().uuidString
        let doc = NSMutableAttributedString(attributedString:
            paragraph(attrs: [.embarMention: uuid as NSString], "згадка"))
        doc.append(paragraph("\nхвіст"))
        storage.setAttributedString(doc)

        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 6)))
        let mention = storage.attribute(.embarMention, at: storage.length - 1,
                                        effectiveRange: nil) as? String
        XCTAssertEqual(mention, uuid, "чіп-згадка після драгу перестала бути чіпом")
    }

    /// Драг тексту з хайлайтом: маркер кольору на місці
    func testHighlightSurvivesRealDrop() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let doc = NSMutableAttributedString(attributedString:
            paragraph(attrs: [.embarHighlight: HighlightColor.yellow.rawValue as NSString],
                      "жовте"))
        doc.append(paragraph("\nхвіст"))
        storage.setAttributedString(doc)

        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 5)))
        let hi = storage.attribute(.embarHighlight, at: storage.length - 1,
                                   effectiveRange: nil) as? String
        XCTAssertEqual(hi, HighlightColor.yellow.rawValue,
                       "хайлайт після драгу зник")
    }

    /// Драг заголовка: роль H1 (джерело правди стилю) переживає дроп
    func testHeadingRoleSurvivesRealDrop() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let doc = NSMutableAttributedString(attributedString:
            paragraph(attrs: [.embarRole: ParagraphRole.h1.rawValue as NSString,
                              .font: NoteTypography.font(role: .h1)],
                      "Заголовок\n"))
        doc.append(paragraph("хвіст"))
        storage.setAttributedString(doc)

        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 10)))
        let role = storage.attribute(.embarRole, at: storage.length - 1,
                                     effectiveRange: nil) as? String
        XCTAssertEqual(role, ParagraphRole.h1.rawValue,
                       "роль заголовка після драгу втрачена")
    }

    // MARK: - ⌘Z після дропу (зона двох фризів - обережно з обліком undo)

    /// Undo дропу повертає документ дослівно; redo повторює; облік undo
    /// не розсипається (пара shouldChangeText → didChangeText у
    /// readSelection мусить лишатись збалансованою)
    func testUndoAfterDropRestoresDocument() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let ids = [UUID().uuidString]
        let doc = NSMutableAttributedString(attachment:
            EmbarPhotoRowAttachment(imageIDs: ids, columns: 1))
        doc.append(paragraph("\nхвіст"))
        storage.setAttributedString(doc)
        let before = storage.string

        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 2)))
        let after = storage.string
        XCTAssertNotEqual(before, after)

        let undo = coordinator.editorUndoManager
        XCTAssertTrue(undo.canUndo, "дроп не зареєструвався в undo")
        undo.undo()
        XCTAssertEqual(storage.string, before, "⌘Z після дропу не повернув документ")
        undo.redo()
        XCTAssertEqual(storage.string, after, "redo після undo дропу не повторив вставку")
        undo.undo()
        XCTAssertEqual(storage.string, before)
    }

    // MARK: - Індикатор дропу і снап фото до межі абзацу (фідбек 2026-08-28)

    /// Дроп ряду фото в СЕРЕДИНУ слова приземляється на початок абзацу:
    /// фото не може розірвати слово - лише зсунути текст униз
    func testPhotoDropIntoWordSnapsToParagraphStart() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let ids = [UUID().uuidString]
        let doc = NSMutableAttributedString(attachment:
            EmbarPhotoRowAttachment(imageIDs: ids, columns: 1))
        doc.append(paragraph("\nперший абзац тут\nдругий абзац тут"))
        storage.setAttributedString(doc)
        let second = (storage.string as NSString).range(of: "другий")

        // Точка - всередині слова «другий» (верхня половина рядка)
        XCTAssertTrue(drag(tv, range: NSRange(location: 0, length: 2),
                           to: midWordPoint(tv, at: second.location + 3)))

        // Attachment сів РІВНО на початок абзацу «другий…», не в слово
        let att = storage.attribute(.attachment, at: second.location,
                                    effectiveRange: nil) as? EmbarPhotoRowAttachment
        XCTAssertEqual(att?.imageIDs, ids,
                       "фото не на початку абзацу - снап не спрацював")
        XCTAssertTrue(storage.string.contains("другий абзац тут"),
                      "дроп розірвав слово: \(storage.string)")
    }

    /// Під час наведення індикатор живе і показує межу абзацу (режим
    /// «цілим рядом»); вихід за межі вьюхи його гасить
    func testDropIndicatorTracksAndClears() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let doc = NSMutableAttributedString(attachment:
            EmbarPhotoRowAttachment(imageIDs: [UUID().uuidString], columns: 1))
        doc.append(paragraph("\nперший абзац тут\nдругий абзац тут"))
        storage.setAttributedString(doc)
        let second = (storage.string as NSString).range(of: "другий")

        let info = try XCTUnwrap(beginDrag(tv, range: NSRange(location: 0, length: 2),
                                           to: midWordPoint(tv, at: second.location + 3)))
        _ = tv.draggingEntered(info)
        _ = tv.draggingUpdated(info)
        let ind = try XCTUnwrap(tv.dropIndicator, "індикатор не зʼявився під час драгу")
        XCTAssertTrue(ind.wholeRow, "фрагмент із фото мусить показувати планку ряду")
        XCTAssertEqual(ind.index, second.location, "індикатор не на межі абзацу")

        tv.draggingExited(info)
        XCTAssertNil(tv.dropIndicator, "індикатор лишився після виходу драгу")
    }

    /// Чистий текст індикатор не снапить: точна позиція, режим каретки
    func testTextDropIndicatorIsExact() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        storage.setAttributedString(paragraph("перший абзац тут\nдругий абзац тут"))
        let second = (storage.string as NSString).range(of: "другий")
        let target = second.location + 3

        let info = try XCTUnwrap(beginDrag(tv, range: NSRange(location: 0, length: 6),
                                           to: midWordPoint(tv, at: target)))
        _ = tv.draggingEntered(info)
        _ = tv.draggingUpdated(info)
        let ind = try XCTUnwrap(tv.dropIndicator)
        XCTAssertFalse(ind.wholeRow, "текст без фото - режим точної каретки")
        XCTAssertEqual(ind.index, target, "каретка не в точці наведення")
    }

    // MARK: - Файлові драги (фідбек 2026-08-28): відхиляти, не сипати шлях

    /// Драг файлу (скріншот, Finder) не вставляє «/var/folders/…» текстом:
    /// дроп відхиляється цілком, документ не змінюється
    func testFileDragIsRefused() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        storage.setAttributedString(paragraph("текст нотатки"))
        let before = storage.string

        let pb = NSPasteboard(name: NSPasteboard.Name("EmbarTestFileDrag"))
        pb.clearContents()
        // Як тягне Finder/скріншот: file-url + шлях плейн-текстом
        pb.declareTypes([.fileURL, .string], owner: nil)
        pb.setString("file:///tmp/Screenshot.png", forType: .fileURL)
        pb.setString("/tmp/Screenshot.png", forType: .string)

        let info = FakeDrag(pb: pb, window: window, source: nil,
                            location: tv.convert(NSPoint(x: 50, y: 10), to: nil))
        XCTAssertEqual(tv.draggingEntered(info), [], "файловий драг мав бути відхилений")
        XCTAssertEqual(tv.draggingUpdated(info), [])
        XCTAssertNil(tv.dropIndicator)
        XCTAssertFalse(tv.performDragOperation(info), "страховка performDrag не спрацювала")
        XCTAssertEqual(storage.string, before, "файловий драг змінив документ")
    }

    // MARK: - Шлях ⌘V (перша половина фікса) - тримаємо теж

    func testPhotoRowSurvivesCopyPasteRoundTrip() throws {
        let tv = makeTextView()
        let storage = try XCTUnwrap(tv.textStorage)
        let ids = [UUID().uuidString, UUID().uuidString]
        let doc = NSMutableAttributedString(attachment:
            EmbarPhotoRowAttachment(imageIDs: ids, columns: 2))
        doc.append(paragraph("\nхвіст"))
        storage.setAttributedString(doc)

        tv.setSelectedRange(NSRange(location: 0, length: 1))
        let pb = NSPasteboard(name: NSPasteboard.Name("EmbarTestPaste"))
        pb.clearContents()
        XCTAssertTrue(tv.writeSelection(to: pb, types: tv.writablePasteboardTypes))
        tv.setSelectedRange(NSRange(location: storage.length, length: 0))
        XCTAssertTrue(tv.readSelection(from: pb))

        let dropped = storage.attribute(.attachment, at: storage.length - 1,
                                        effectiveRange: nil) as? EmbarPhotoRowAttachment
        let row = try XCTUnwrap(dropped, "⌘V нашого фрагмента втратив фото")
        XCTAssertEqual(row.imageIDs, ids)
        XCTAssertEqual(row.columns, 2)
    }
}
