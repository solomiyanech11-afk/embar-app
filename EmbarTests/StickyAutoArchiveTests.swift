//
//  StickyAutoArchiveTests.swift
//  EmbarTests
//
//  Автоархів забирає стік зі стіни сам, тихо і без undo — розархівувати
//  його людина не може. Тому найдорожче правило тут не «коли архівувати»,
//  а «коли НЕ архівувати»: відлік не має діяти заднім числом.
//
//  Два сценарії, через які стіки колись поїхали в архів пачкою
//  (ревʼю 2026-08-20):
//  1. Оновлення застосунку: міграція звільнила стіки з індивідуальним
//     «не архівувати», а відлік ішов від updatedAt у минулому.
//  2. Зміна строку в налаштуваннях: «3 місяці → 1 тиждень» одразу
//     робило простроченим усе, що виконано давніше за тиждень.
//

import XCTest
import SwiftData
@testable import Embar

@MainActor
final class StickyAutoArchiveTests: XCTestCase {

    private var savedDays: Any?
    private var savedTermChanged: Any?
    private let store = EmbarDefaults.store

    override func setUp() {
        super.setUp()
        savedDays = store.object(forKey: StickyAutoArchive.storageKey)
        savedTermChanged = store.object(forKey: StickyAutoArchive.termChangedKey)
        store.removeObject(forKey: StickyAutoArchive.termChangedKey)
        store.set(7, forKey: StickyAutoArchive.storageKey)
    }

    override func tearDown() {
        restore(savedDays, forKey: StickyAutoArchive.storageKey)
        restore(savedTermChanged, forKey: StickyAutoArchive.termChangedKey)
        container = nil
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
    }

    /// Контейнер тримаємо у властивості: локальний звільнився б, і його
    /// mainContext повалив би SwiftData на першому ж fetch
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    private func days(_ count: Double) -> TimeInterval { count * 86400 }

    // MARK: - Сценарій 1: стік без відліку (оновлення / міграція)

    /// ❗ Головний тест файлу. Виконаний два місяці тому стік, який до
    /// оновлення не архівувався, НЕ має поїхати в архів на першому ж
    /// запуску з новими правилами
    func testStickerWithoutCountdownIsNotArchivedOnFirstRun() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний два місяці тому")
        sticker.done = true
        sticker.updatedAt = now.addingTimeInterval(-days(60))
        sticker.archiveCountdownAt = nil // так виглядають дані до оновлення
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertFalse(sticker.archived,
                       "стік не бачив нових правил жодного дня — в архів зарано")
        XCTAssertEqual(sticker.archiveCountdownAt, now,
                       "відлік починається зараз, а не від updatedAt у минулому")
    }

    /// ...але потім усе одно поїде: правило не скасовується, лише зсувається
    func testCountdownRunsFromFirstRunAndArchivesLater() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний два місяці тому")
        sticker.done = true
        sticker.updatedAt = now.addingTimeInterval(-days(60))
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)
        XCTAssertFalse(sticker.archived)

        // Строк — тиждень: на восьмий день після ПЕРШОГО запуску
        AppMaintenance.run(in: context, now: now.addingTimeInterval(days(8)))

        XCTAssertTrue(sticker.archived, "повний строк на стіні минув — тепер можна")
        XCTAssertNotNil(sticker.archivedAt, "30 днів до видалення рахуються з цієї миті")
    }

    // MARK: - Сценарій 2: людина скоротила строк у налаштуваннях

    func testShorteningTermDoesNotArchiveRetroactively() throws {
        let context = try makeContext()
        let now = Date.now
        store.set(90, forKey: StickyAutoArchive.storageKey)

        let sticker = Sticker(text: "Виконаний місяць тому")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(30))
        context.insert(sticker)

        // Місяць при строку «3 місяці» — ще рано
        AppMaintenance.run(in: context, now: now)
        XCTAssertFalse(sticker.archived)

        // Людина перемикає на «1 тиждень». Стік виконано 30 днів тому,
        // тобто за новим строком він «прострочений» — але змітати його
        // тим самим запуском не можна
        store.set(7, forKey: StickyAutoArchive.storageKey)
        StickyAutoArchive.noteTermChange(at: now)

        AppMaintenance.run(in: context, now: now.addingTimeInterval(1))

        XCTAssertFalse(sticker.archived,
                       "новий строк не діє заднім числом — стік лишається на стіні")
    }

    func testShortenedTermStillArchivesAfterFullTerm() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний місяць тому")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(30))
        context.insert(sticker)

        StickyAutoArchive.noteTermChange(at: now) // щойно поставили тиждень

        AppMaintenance.run(in: context, now: now.addingTimeInterval(days(8)))

        XCTAssertTrue(sticker.archived, "тиждень від зміни строку минув")
    }

    /// Подовження строку теж позначається зміною — і це нікому не шкодить:
    /// відлік лише відсувається, жоден стік від цього не зникає раніше
    func testLengtheningTermNeverArchivesSooner() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний тиждень тому")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(8))
        context.insert(sticker)

        store.set(90, forKey: StickyAutoArchive.storageKey)
        StickyAutoArchive.noteTermChange(at: now)

        AppMaintenance.run(in: context, now: now.addingTimeInterval(days(9)))

        XCTAssertFalse(sticker.archived)
    }

    // MARK: - Звичайний хід

    func testDoneStickerArchivesAfterTerm() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Звичайний виконаний")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(8))
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertTrue(sticker.archived)
    }

    func testDoneStickerSurvivesInsideTerm() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний позавчора")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(2))
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertFalse(sticker.archived)
    }

    /// Активний стік не архівується ніколи, хай яким давнім він буде
    func testActiveStickerIsNeverArchived() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Просто висить рік")
        sticker.updatedAt = now.addingTimeInterval(-days(365))
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertFalse(sticker.archived)
        XCTAssertNil(sticker.archiveCountdownAt, "активному стіку немає що рахувати")
    }

    // MARK: - Старт і скидання відліку

    func testToggleDoneStartsCountdown() throws {
        let sticker = Sticker(text: "Зробили щойно")
        StickerService.toggleDone(sticker)

        XCTAssertTrue(sticker.done)
        XCTAssertNotNil(sticker.archiveCountdownAt, "відлік стартує в момент виконання")
    }

    /// §15.44б: зняли «зроблено» — цикл наново
    func testUndoneStickerLosesCountdown() throws {
        let sticker = Sticker(text: "Передумали")
        StickerService.toggleDone(sticker)
        StickerService.toggleDone(sticker)

        XCTAssertFalse(sticker.done)
        XCTAssertNil(sticker.archiveCountdownAt)
    }

    /// Те саме, але коли «зроблено» зняли до появи поля — прибирає
    /// обслуговування бази
    func testMaintenanceClearsCountdownOfActiveSticker() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Активний зі старим відліком")
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(30))
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertNil(sticker.archiveCountdownAt)
        XCTAssertFalse(sticker.archived)
    }

    /// Правка виконаного стіка більше не відсуває архів безкінечно:
    /// відлік прив'язаний до моменту виконання, а не до updatedAt
    func testEditingDoneStickerDoesNotPostponeArchive() throws {
        let context = try makeContext()
        let now = Date.now
        let sticker = Sticker(text: "Виконаний і потім правлений")
        sticker.done = true
        sticker.archiveCountdownAt = now.addingTimeInterval(-days(8))
        sticker.updatedAt = now // щойно правили текст
        context.insert(sticker)

        AppMaintenance.run(in: context, now: now)

        XCTAssertTrue(sticker.archived)
    }
}
