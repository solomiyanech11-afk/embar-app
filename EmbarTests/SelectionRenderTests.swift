//
//  SelectionRenderTests.swift
//  EmbarTests
//
//  Сторож механізму виділення (ревʼю 2026-08-18, знахідка 1).
//
//  Історія: заливку виділення прибирали через
//  `selectedTextAttributes = [.backgroundColor: .clear]`. Ці атрибути
//  AppKit бере, ЛИШЕ поки вьюха - first responder. Досить було клацнути
//  в поле назви - і система знову малювала свою смугу на всю рядкову
//  коробку, тобто рівно той грубий вигляд, заради якого власне
//  малювання й робилось.
//
//  Тепер шлях перекрито в layout manager, і тест тримає дві речі:
//  · сам гасник справді нічого не малює;
//  · жодна вьюха не покладається на самі атрибути - хто прибирає
//    системну заливку, той мусить поставити й EmbarSelectionLayoutManager.
//

import XCTest
import AppKit
@testable import Embar

final class SelectionRenderTests: XCTestCase {

    // MARK: - Гасник справді гасить

    /// Малюємо заливку в білий бітмап через наш layout manager: жоден
    /// піксель не сміє змінитись
    // MARK: - Один тон на три шляхи малювання (рішення 2026-08-20)

    /// Виділення малюють три різні механізми: наші вьюхи самі, поля —
    /// система за `AppleHighlightColor`, тіло стіка — SwiftUI за
    /// АКЦЕНТОМ. Саме через це вони колись розійшлись (стік рожевий,
    /// решта графітова). Тест тримає їх на одному тоні
    func testAllThreePathsShareOneHue() throws {
        func rgb(_ c: NSColor) throws -> (CGFloat, CGFloat, CGFloat) {
            let s = try XCTUnwrap(c.usingColorSpace(.sRGB))
            return (s.redComponent, s.greenComponent, s.blueComponent)
        }
        // Наш тон і акцент, яким малює SwiftUI, — це той самий колір
        let ours = try rgb(EmbarSelection.tint)
        let accent = try rgb(NSColor(embarHex: "#FF5257"))
        XCTAssertEqual(ours.0, accent.0, accuracy: 0.01)
        XCTAssertEqual(ours.1, accent.1, accuracy: 0.01)
        XCTAssertEqual(ours.2, accent.2, accuracy: 0.01)

        // Червоний, а не сірий: у сірого канали майже рівні
        XCTAssertGreaterThan(ours.0 - ours.1, 0.3, "виділення мусить бути червонуватим")
    }

    /// `flattened` (той, що їде в AppleHighlightColor) мусить бути ТОЧНО
    /// нашим напівпрозорим тоном, накладеним на папір панелі, — інакше
    /// поле вводу і тіло нотатки поруч виглядали б різними
    func testFlattenedMatchesTintOverPaper() throws {
        let paper = try XCTUnwrap(NSColor(embarHex: "#fcfbf9").usingColorSpace(.sRGB))
        let tint = try XCTUnwrap(EmbarSelection.tint.usingColorSpace(.sRGB))
        let flat = try XCTUnwrap(EmbarSelection.flattened.usingColorSpace(.sRGB))
        let a = tint.alphaComponent

        XCTAssertEqual(flat.redComponent,
                       tint.redComponent * a + paper.redComponent * (1 - a), accuracy: 0.004)
        XCTAssertEqual(flat.greenComponent,
                       tint.greenComponent * a + paper.greenComponent * (1 - a), accuracy: 0.004)
        XCTAssertEqual(flat.blueComponent,
                       tint.blueComponent * a + paper.blueComponent * (1 - a), accuracy: 0.004)
        XCTAssertEqual(flat.alphaComponent, 1, "AppleHighlightColor альфи не має")
    }

    /// Виділення мусить лишатись напівпрозорим: під ним у тілі нотатки
    /// лежать хайлайти пера, і непрозора заливка затерла б їх замість
    /// притемнити (саме цим «виділене підсвічене» відрізняється від
    /// просто підсвіченого)
    func testTintStaysTranslucentSoHighlightsShowThrough() {
        XCTAssertLessThan(EmbarSelection.tint.alphaComponent, 0.5)
        XCTAssertGreaterThan(EmbarSelection.tint.alphaComponent, 0)
    }

    /// ❗ Тихий стан - СИСТЕМНИЙ сірий, а не наш блідий червоний: у полях
    /// і в тілі стіка малює система, і виглядати воно мусить так само
    /// (фідбек 2026-08-21). Свій відтінок тут означав би, що нотатка
    /// знову єдина не така, як усі
    func testInactiveSelectionIsTheSystemOne() {
        XCTAssertEqual(EmbarSelection.inactive,
                       NSColor.unemphasizedSelectedTextBackgroundColor)
    }

    /// Правило «гучного» виділення мусить вимагати ще й key-вікна:
    /// без цього наші вьюхи лишались яскравими, коли людина йшла в
    /// іншу програму, а стіки поруч тихішали
    func testEmphasisNeedsAKeyWindowNotJustFirstResponder() {
        let orphan = NSView() // без вікна взагалі
        XCTAssertFalse(EmbarSelection.isEmphasized(orphan))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let view = NSView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(view)
        // Вікно не key (у тестах його ніхто не активує) — навіть ставши
        // first responder, вьюха «гучною» не стає
        window.makeFirstResponder(view)
        XCTAssertFalse(EmbarSelection.isEmphasized(view),
                       "вікно не key — виділення мусить бути тихим")
    }

    func testLayoutManagerDrawsNoBackgroundFill() throws {
        let size = NSSize(width: 40, height: 20)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let rects = [NSRect(origin: .zero, size: size)]
        let manager = EmbarSelectionLayoutManager()
        rects.withUnsafeBufferPointer { buffer in
            guard let first = buffer.baseAddress else { return }
            manager.fillBackgroundRectArray(
                first, count: buffer.count,
                forCharacterRange: NSRange(location: 0, length: 1),
                color: .red)
        }
        NSGraphicsContext.restoreGraphicsState()

        let middle = try XCTUnwrap(rep.colorAt(x: Int(size.width) / 2,
                                               y: Int(size.height) / 2))
        let white = try XCTUnwrap(NSColor.white.usingColorSpace(.deviceRGB))
        let drawn = try XCTUnwrap(middle.usingColorSpace(.deviceRGB))
        XCTAssertEqual(drawn.redComponent, white.redComponent, accuracy: 0.01,
                       "layout manager намалював заливку - виділення знову буде системним")
        XCTAssertEqual(drawn.greenComponent, white.greenComponent, accuracy: 0.01)
        XCTAssertEqual(drawn.blueComponent, white.blueComponent, accuracy: 0.01)
    }

    // MARK: - Сторож вихідників

    private var appSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EmbarTests
            .deletingLastPathComponent()   // корінь
            .appendingPathComponent("Embar")
        return (FileManager.default.enumerator(at: root,
                                               includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            // Дебаг-стенди - не продуктові поверхні: їхній вигляд нікого
            // не обходить, і живуть вони до першого прибирання
            .filter { !$0.pathComponents.contains("Debug") }) ?? []
    }

    /// Хто прибирає системну заливку виділення атрибутами - той мусить
    /// поставити й гасник. Інакше вьюха виглядатиме правильно рівно
    /// доти, доки в ній курсор
    func testEveryCustomSelectionAlsoInstallsTheLayoutManager() throws {
        var offenders: [String] = []
        for file in appSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            let usesCustomSelection = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .contains { line in
                    line.contains("selectedTextAttributes")
                        && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                }
            guard usesCustomSelection else { continue }
            if !text.contains("EmbarSelectionLayoutManager") {
                offenders.append(file.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Ці вьюхи прибирають системне виділення атрибутами, але не ставлять \
            EmbarSelectionLayoutManager - при втраті фокуса система намалює \
            свою грубу смугу: \(offenders.joined(separator: ", "))
            """)
    }
}
