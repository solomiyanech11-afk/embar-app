//
//  StickyMigrationsTests.swift
//  EmbarTests
//
//  Міграції даних стіків проходять по РЕАЛЬНІЙ базі людини і працюють
//  один раз — помилка тут мовчазна й невідворотна. Тому кожне правило
//  перевіряємо окремо, і окремо — що повторний запуск нічого не робить.
//

import XCTest
import SwiftData
@testable import Embar

@MainActor
final class StickyMigrationsTests: XCTestCase {

    private var savedDays: Any?

    override func setUp() {
        super.setUp()
        savedDays = EmbarDefaults.store.object(forKey: StickyAutoArchive.storageKey)
        EmbarDefaults.store.removeObject(forKey: StickyAutoArchive.storageKey)
        StickyMigrations.resetFlagsForTesting()
    }

    override func tearDown() {
        if let savedDays {
            EmbarDefaults.store.set(savedDays, forKey: StickyAutoArchive.storageKey)
        } else {
            EmbarDefaults.store.removeObject(forKey: StickyAutoArchive.storageKey)
        }
        StickyMigrations.resetFlagsForTesting()
        container = nil
        super.tearDown()
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

    // MARK: - Автоархів завжди ввімкнено

    func testIndividualAutoArchiveSettingsAreReset() throws {
        let context = try makeContext()
        let off = Sticker(text: "З вимкненим автоархівом")
        off.autoArchiveOff = true
        let ownTerm = Sticker(text: "З власним строком")
        ownTerm.autoDeleteAt = Date.now.addingTimeInterval(86400)
        context.insert(off)
        context.insert(ownTerm)

        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertFalse(off.autoArchiveOff, "вимикач автоархіву має зникнути")
        XCTAssertNil(ownTerm.autoDeleteAt, "індивідуальний строк має зникнути")
    }

    func testDisabledGlobalTermBecomesMonth() throws {
        let context = try makeContext()
        EmbarDefaults.store.set(0, forKey: StickyAutoArchive.storageKey) // старий «Вимк»

        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertEqual(StickyAutoArchive.days, 30)
    }

    func testChosenGlobalTermSurvives() throws {
        let context = try makeContext()
        EmbarDefaults.store.set(90, forKey: StickyAutoArchive.storageKey)

        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertEqual(StickyAutoArchive.days, 90, "свідомий вибір людини не чіпаємо")
    }

    func testMigrationRunsOnlyOnce() throws {
        let context = try makeContext()
        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        // Після міграції зʼявився стік зі старим полем (наприклад, приїхав
        // із CloudKit) — повторний виклик його не чіпає: прапорець стоїть
        let late = Sticker(text: "Пізній гість")
        late.autoArchiveOff = true
        context.insert(late)
        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertTrue(late.autoArchiveOff)
    }

    // MARK: - Діючий строк

    func testDaysFallsBackToMonthForUnknownValue() {
        EmbarDefaults.store.set(3, forKey: StickyAutoArchive.storageKey)
        XCTAssertEqual(StickyAutoArchive.days, 30)
    }

    // MARK: - Нагадування стало дедлайном

    /// Нагадування без дедлайну саме ним і стає — нагадати в момент
    func testLonelyReminderBecomesDeadline() throws {
        let context = try makeContext()
        let at = Date.now.addingTimeInterval(3600)
        let sticker = Sticker(text: "Подзвонити")
        sticker.reminder = at
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(sticker.deadline, at)
        XCTAssertEqual(sticker.notifyOffsetMinutes, 0)
        XCTAssertNil(sticker.reminder)
    }

    /// Обидві дати: дедлайн лишається, з різниці народжується зсув
    func testExactOffsetIsKept() throws {
        let context = try makeContext()
        let deadline = Date.now.addingTimeInterval(7200)
        let sticker = Sticker(text: "Здати текст")
        sticker.deadline = deadline
        sticker.reminder = deadline.addingTimeInterval(-3600) // рівно за годину
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(sticker.deadline, deadline, "дедлайн не рухається")
        XCTAssertEqual(sticker.notifyOffsetMinutes, 60)
    }

    func testOddOffsetSnapsDown() throws {
        let context = try makeContext()
        let deadline = Date.now.addingTimeInterval(7200)
        let sticker = Sticker(text: "Зустріч")
        sticker.deadline = deadline
        sticker.reminder = deadline.addingTimeInterval(-45 * 60) // за 45 хв
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(sticker.notifyOffsetMinutes, 30, "45 хв → найближчі 30")
    }

    func testReminderAfterDeadlineNotifiesAtTheMoment() throws {
        let context = try makeContext()
        let deadline = Date.now.addingTimeInterval(3600)
        let sticker = Sticker(text: "Перевірити")
        sticker.deadline = deadline
        sticker.reminder = deadline.addingTimeInterval(1800)
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(sticker.notifyOffsetMinutes, 0)
    }

    /// Дедлайн без нагадування лишається БЕЗ сповіщення: людина його не
    /// просила, і після оновлення воно було б несподіванкою
    func testDeadlineWithoutReminderStaysSilent() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "Просто дедлайн")
        sticker.deadline = Date.now.addingTimeInterval(3600)
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertNil(sticker.notifyOffsetMinutes)
    }

    // MARK: - Збій посеред міграції

    private struct StorageFailure: Error {}

    /// ❗ Найдорожчий шлях: якщо база не читається або не зберігається,
    /// прапорець ставити НЕ можна — інакше міграція вважається зробленою
    /// назавжди, а дані лишаються напівстарими (ревʼю 2026-08-19)
    func testFailedFetchDoesNotMarkAutoArchiveMigrationDone() throws {
        StickyMigrations.migrateAutoArchiveAlwaysOn(
            fetch: { throw StorageFailure() }, save: {})

        // Наступний запуск має спрацювати по-справжньому
        let context = try makeContext()
        let sticker = Sticker(text: "З вимкненим автоархівом")
        sticker.autoArchiveOff = true
        context.insert(sticker)
        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertFalse(sticker.autoArchiveOff)
    }

    func testFailedSaveDoesNotMarkAutoArchiveMigrationDone() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "З власним строком")
        sticker.autoDeleteAt = Date.now.addingTimeInterval(86400)
        context.insert(sticker)

        StickyMigrations.migrateAutoArchiveAlwaysOn(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { throw StorageFailure() })

        // Пам'ять уже змінена, але прапорця немає — повторний прохід
        // доведе справу до кінця і збереже
        sticker.autoDeleteAt = Date.now.addingTimeInterval(86400)
        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)

        XCTAssertNil(sticker.autoDeleteAt)
    }

    /// Збій не робить міграцію «зробленою»: наступний прохід доводить
    /// справу до кінця (прапорця в цієї міграції більше немає — вона
    /// щоразу шукає стіки з живим `reminder`)
    func testFailedSaveStillLetsNextRunFinishTheJob() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "З нагадуванням")
        let at = Date.now.addingTimeInterval(3600)
        sticker.reminder = at
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { throw StorageFailure() })

        // Нагадування не має зникнути мовчки: повертаємо як було і
        // переконуємось, що другий прохід його таки перенесе
        sticker.reminder = at
        sticker.deadline = nil
        sticker.notifyOffsetMinutes = nil
        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(sticker.deadline, at)
        XCTAssertEqual(sticker.notifyOffsetMinutes, 0)
    }

    /// Композит: обидві міграції за один прохід і жодного повтору
    func testRunAppliesBothMigrations() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "Старий стік")
        sticker.autoArchiveOff = true
        sticker.reminder = Date.now.addingTimeInterval(3600)
        context.insert(sticker)

        StickyMigrations.run(in: context)

        XCTAssertFalse(sticker.autoArchiveOff)
        XCTAssertNotNil(sticker.deadline)
        XCTAssertNil(sticker.reminder)
    }

    /// ❗ Раніше цей тест перевіряв протилежне — що пізнього гостя НЕ
    /// чіпають, бо міграція вже «зроблена». Прапорець виявився пасткою:
    /// поле `reminder` ніхто більше не читає, а стік із ним може приїхати
    /// й після міграції (CloudKit у M6) — нагадування зникло б мовчки
    /// (ревʼю 2026-08-20)
    func testLateArrivalIsStillMigrated() throws {
        let context = try makeContext()
        StickyMigrations.migrateReminderIntoDeadline(in: context)

        let late = Sticker(text: "Пізній гість")
        let at = Date.now.addingTimeInterval(3600)
        late.reminder = at
        context.insert(late)
        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertEqual(late.deadline, at, "нагадування не має зникнути")
        XCTAssertEqual(late.notifyOffsetMinutes, 0)
        XCTAssertNil(late.reminder)
    }

    /// Стіків із застарілим полем немає — міграція мовчить і нічого не
    /// чіпає (перевіряємо, що щоразовий прохід не має побічних дій)
    func testNothingToMigrateLeavesStickersAlone() throws {
        let context = try makeContext()
        let plain = Sticker(text: "Звичайний")
        plain.deadline = Date.now.addingTimeInterval(3600)
        context.insert(plain)

        StickyMigrations.migrateReminderIntoDeadline(in: context)

        XCTAssertNil(plain.notifyOffsetMinutes,
                     "дедлайн без нагадування лишається без сповіщення")
    }

    // MARK: - Відкат при збої (ревʼю 2026-08-20)

    /// ❗ Прапорця мало: зміни вже лежать у контексті, і автозбереження
    /// SwiftData винесло б їх у базу попри збій. Без відкату наступний
    /// запуск знайшов би `autoArchiveOff` уже скинутим і вважав роботу
    /// зробленою.
    ///
    /// Відкат саме РУЧНИЙ: `context.rollback()` не повертає значення вже
    /// змінених обʼєктів — перша версія цього тесту падала саме на ньому
    func testFailedSaveRollsBackAutoArchiveChanges() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "З власним строком")
        let until = Date.now.addingTimeInterval(86400)
        sticker.autoDeleteAt = until
        sticker.autoArchiveOff = true
        context.insert(sticker)

        StickyMigrations.migrateAutoArchiveAlwaysOn(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { throw StorageFailure() })

        XCTAssertEqual(sticker.autoDeleteAt, until, "зміна не мала пережити збій")
        XCTAssertTrue(sticker.autoArchiveOff)

        // І наступний прохід доводить справу до кінця
        StickyMigrations.migrateAutoArchiveAlwaysOn(in: context)
        XCTAssertNil(sticker.autoDeleteAt)
        XCTAssertFalse(sticker.autoArchiveOff)
    }

    /// Те саме для нагадувань — тут ціна помилки найвища: `reminder`
    /// занулюється, і без відкату переносити наступного разу вже нічого
    func testFailedSaveRollsBackReminderChanges() throws {
        let context = try makeContext()
        let sticker = Sticker(text: "З нагадуванням")
        let at = Date.now.addingTimeInterval(3600)
        sticker.reminder = at
        context.insert(sticker)

        StickyMigrations.migrateReminderIntoDeadline(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { throw StorageFailure() })

        XCTAssertEqual(sticker.reminder, at, "нагадування мусить лишитись на місці")
        XCTAssertNil(sticker.deadline)
        XCTAssertNil(sticker.notifyOffsetMinutes)

        // І наступний прохід доводить справу до кінця
        StickyMigrations.migrateReminderIntoDeadline(in: context)
        XCTAssertEqual(sticker.deadline, at)
        XCTAssertNil(sticker.reminder)
    }
}
