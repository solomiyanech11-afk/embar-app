//
//  ProGateTests.swift
//  EmbarTests
//
//  Гейт режиму читання (SPEC §15.77ґ): поведінка allowCreate і -
//  головне - source-scan карти точок створення. Карта з плану
//  монетизації 2026-09-16 закріплена як код: файл, що мусить мати
//  гейт, без виклику ProGate.allowCreate не пройде CI. Той самий
//  прийом, що DebugGuardTests.
//

import XCTest
@testable import Embar

final class ProGateTests: XCTestCase {

    // MARK: - Карта гейтів (файл → мусить кликати ProGate.allowCreate)
    //
    // Точки всередині файлів: композер стіків і matureSticky і стіни
    // (StickiesView), стіна з розгорнутого стіка (StickyExpandedView),
    // композер нотаток і папки (NotesView), папка з редактора
    // (NoteEditorView), «＋ Створити» зі згадок (NoteEditorModel),
    // папки й новий блокнот (ReaderView), запис/тема/highlight/цитата
    // в нову/папка (ReaderNotebookView), submit і мікрофон
    // (ReaderComposeBar)
    private static let gatedFiles: Set<String> = [
        "StickiesView.swift",
        "StickyExpandedView.swift",
        "NotesView.swift",
        "NoteEditorView.swift",
        "NoteEditorModel.swift",
        "ReaderView.swift",
        "ReaderNotebookView.swift",
        "ReaderComposeBar.swift",
    ]

    /// Недосяжні шляхи (Home вимкнено, addToTodos мертвий) - тихий гард
    /// без тосту прямо в сервісі
    private static let silentlyGuardedFiles: Set<String> = [
        "HomeService.swift",
        "StickerService.swift",
    ]

    private var appSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Embar")
        return (FileManager.default.enumerator(at: root,
                                               includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
    }

    func testEveryMappedFileHasGate() throws {
        var missing = Set(Self.gatedFiles)
        var missingSilent = Set(Self.silentlyGuardedFiles)
        for file in appSources {
            let name = file.lastPathComponent
            if missing.contains(name),
               try String(contentsOf: file, encoding: .utf8)
                   .contains("ProGate.allowCreate") {
                missing.remove(name)
            }
            if missingSilent.contains(name),
               try String(contentsOf: file, encoding: .utf8)
                   .contains("EntitlementStore.shared.canCreate") {
                missingSilent.remove(name)
            }
        }
        XCTAssertTrue(missing.isEmpty, """
            Файли з карти створення без ProGate.allowCreate: \(missing). \
            Хтось прибрав гейт режиму читання - поверни або онови карту \
            свідомим рішенням.
            """)
        XCTAssertTrue(missingSilent.isEmpty, """
            Сервіси без тихого гарда canCreate: \(missingSilent)
            """)
    }

    // MARK: - Поведінка на живому сторі

    func testAllowCreateFollowsAccessState() {
        let store = EntitlementStore.shared
        let keychain = MockKeychain()
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
        defer { restoreShared() }

        store.bootstrap(now: start, backing: keychain)
        XCTAssertTrue(store.canCreate, "trial - створювати можна")

        // Через 15 днів RC каже «не pro» → режим читання
        store.applyProStatus(false, isSubscription: false,
                             now: start.addingTimeInterval(15 * 86_400))
        XCTAssertFalse(store.canCreate)
        XCTAssertFalse(ProGate.allowCreate(), "гейт мусить відмовити")

        // Покупка знімає режим читання миттєво
        store.applyProStatus(true, isSubscription: false,
                             now: start.addingTimeInterval(15 * 86_400))
        XCTAssertTrue(ProGate.allowCreate())
    }

    /// Спільний singleton - після тесту повертаємо чистий стан, щоб
    /// інші тести не успадкували режим читання
    private func restoreShared() {
        let d = EmbarDefaults.store
        d.removeObject(forKey: EntitlementStore.cacheKey)
        d.removeObject(forKey: EntitlementStore.cacheSubscriptionKey)
        d.removeObject(forKey: TrialAnchor.fallbackKey)
        EntitlementStore.shared.bootstrap(now: .now, backing: MockKeychain())
        d.removeObject(forKey: TrialAnchor.fallbackKey)
    }
}
