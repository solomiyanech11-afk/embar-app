//
//  ReminderSchedulerTests.swift
//  EmbarTests
//
//  Правила відбору: кому взагалі належить сповіщення про дедлайн.
//  Помилка тут або мовчить (сповіщення не прийде), або галасує (прийде
//  про виконаний чи видалений стік), тож перевіряємо кожну умову окремо.
//  Саму систему сповіщень не чіпаємо — тестуємо чисту функцію job(for:).
//

import XCTest
import SwiftData
import UserNotifications
@testable import Embar

@MainActor
final class ReminderSchedulerTests: XCTestCase {

    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    /// Живий стік із дедлайном у майбутньому і зсувом
    private func makeSticker(in context: ModelContext,
                             offset: Int? = 0,
                             deadlineIn seconds: TimeInterval = 3600) -> Sticker {
        let sticker = Sticker(text: "Здати текст")
        sticker.deadline = Date.now.addingTimeInterval(seconds)
        sticker.notifyOffsetMinutes = offset
        context.insert(sticker)
        return sticker
    }

    func testLiveStickerWithDeadlineGetsJob() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context)
        sticker.bodyText = "Розділ про сон"

        let job = try XCTUnwrap(ReminderScheduler.job(for: sticker))

        XCTAssertEqual(job.id, sticker.id)
        XCTAssertEqual(job.title, "Здати текст")
        XCTAssertEqual(job.details, "Розділ про сон")
        XCTAssertEqual(job.at, sticker.deadline)
    }

    func testOffsetShiftsTriggerBeforeDeadline() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, offset: 30, deadlineIn: 7200)

        let job = try XCTUnwrap(ReminderScheduler.job(for: sticker))

        XCTAssertEqual(job.at, sticker.deadline?.addingTimeInterval(-1800))
    }

    func testNilOffsetMeansNoNotification() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, offset: nil)

        XCTAssertNil(ReminderScheduler.job(for: sticker))
    }

    func testNoDeadlineMeansNoNotification() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context)
        sticker.deadline = nil

        XCTAssertNil(ReminderScheduler.job(for: sticker))
    }

    func testDoneArchivedAndDeletedStickersStaySilent() throws {
        let context = try makeContext()

        let done = makeSticker(in: context)
        done.done = true
        XCTAssertNil(ReminderScheduler.job(for: done), "виконаний не нагадує про себе")

        let archived = makeSticker(in: context)
        archived.archived = true
        XCTAssertNil(ReminderScheduler.job(for: archived), "архів — вітрина")

        let deleted = makeSticker(in: context)
        deleted.deletedAt = .now
        XCTAssertNil(ReminderScheduler.job(for: deleted), "банер не переживає стік")
    }

    /// Сповіщень «навздогін» не буває
    func testPastTriggerIsNotScheduled() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, deadlineIn: -60)

        XCTAssertNil(ReminderScheduler.job(for: sticker))
    }

    /// Зсув може відсунути тригер у минуле, хоч дедлайн ще попереду
    func testOffsetThatFallsInThePastIsNotScheduled() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, offset: 1440, deadlineIn: 3600)

        XCTAssertNil(ReminderScheduler.job(for: sticker))
    }

    /// Тіло сповіщення показує стіну — але не soft-видалену
    func testDeletedWallIsNotNamedInBody() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context)
        let wall = Wall(name: "Робота")
        context.insert(wall)
        sticker.wall = wall

        XCTAssertEqual(ReminderScheduler.job(for: sticker)?.wallName, "Робота")

        wall.deletedAt = .now
        XCTAssertNil(ReminderScheduler.job(for: sticker)?.wallName)
    }

    // MARK: - Довжина тексту в банері

    /// Коротке лишається як є — жодних «…» на рівному місці
    func testShortTextIsNotClipped() {
        XCTAssertEqual(ReminderScheduler.clip("Здати текст", limit: 60),
                       "Здати текст")
    }

    /// Рівно по ліміту — ще не довге
    func testTextExactlyAtLimitIsNotClipped() {
        let text = String(repeating: "а", count: 60)
        XCTAssertEqual(ReminderScheduler.clip(text, limit: 60), text)
    }

    /// Довге ріжеться по межі слова: жодного обрубка посеред слова
    func testLongTextIsClippedAtWordBoundary() {
        let text = "Зателефонувати в клініку і перенести візит на наступний тиждень"
        let clipped = ReminderScheduler.clip(text, limit: 60)

        XCTAssertTrue(clipped.hasSuffix("…"), "обрізане має закінчуватись трикрапкою")
        XCTAssertLessThanOrEqual(clipped.count, 61, "трикрапка — єдиний надлишок")
        XCTAssertTrue(text.hasPrefix(clipped.dropLast()),
                      "початок тексту має лишитись недоторканим")
        XCTAssertFalse(clipped.dropLast().hasSuffix(" "), "пробіл перед «…» прибрано")
        // Останнє вціліле слово лишилось цілим: наступний символ у
        // початковому тексті — пробіл, а не продовження слова
        XCTAssertEqual(text.dropFirst(clipped.count - 1).first, " ")
    }

    /// Одне довге слово (посилання) різати назад нікуди — ріжемо по ліміту,
    /// інакше від заголовка не лишилось би нічого
    func testSingleLongWordIsClippedHard() {
        let text = "Коротко " + String(repeating: "х", count: 90)
        let clipped = ReminderScheduler.clip(text, limit: 60)

        XCTAssertEqual(clipped.count, 61, "60 символів + трикрапка")
        XCTAssertTrue(clipped.hasPrefix("Коротко х"))
    }

    /// Переноси рядків у заголовку банера все одно схлопуються
    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(ReminderScheduler.clip("  Купити\nхліб  ", limit: 60),
                       "Купити хліб")
    }

    /// Обрізання живе в job(for:) — у банер іде вже готовий текст.
    /// Ліміт заголовка враховує префікс «Нагадування:» (+1 — трикрапка)
    func testJobCarriesClippedTitleAndDetails() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context)
        sticker.text = String(repeating: "т", count: 200)
        sticker.bodyText = String(repeating: "д", count: 400)

        let job = try XCTUnwrap(ReminderScheduler.job(for: sticker))

        XCTAssertEqual(job.title.count, ReminderScheduler.titleTextLimit + 1)
        XCTAssertEqual(job.details.count, ReminderScheduler.bodyLimit + 1)
        // Префікс + пробіл + текст не вилазять за загальний ліміт
        XCTAssertLessThanOrEqual(
            ReminderScheduler.titlePrefix.count + 1 + job.title.count,
            ReminderScheduler.titleLimit + 1)
    }

    // MARK: - Фінальний вміст банера (не проміжний job)

    private func makeJob(title: String = "Здати текст",
                         details: String = "",
                         wallName: String? = nil) -> ReminderScheduler.Job {
        .init(id: UUID(), title: title, details: details,
              wallName: wallName, at: .now.addingTimeInterval(3600))
    }

    /// Заголовок = «Нагадування: {текст}», ніколи не порожній —
    /// порожнього одного разу вже шукали всім селом (2026-08-19)
    func testContentTitleHasPrefixAndText() {
        let content = ReminderScheduler.content(for: makeJob())

        XCTAssertEqual(content.title,
                       ReminderScheduler.titlePrefix + " Здати текст")
        XCTAssertFalse(content.title.isEmpty)
    }

    /// Стік без тексту → «Нагадування: Стік», а не голий префікс
    func testContentFallsBackWhenTextEmpty() {
        let content = ReminderScheduler.content(for: makeJob(title: ""))

        XCTAssertTrue(content.title.hasPrefix(ReminderScheduler.titlePrefix))
        XCTAssertGreaterThan(content.title.count,
                             ReminderScheduler.titlePrefix.count + 1)
    }

    /// Тіло: деталі й стіна через новий рядок; порожні частини не лишають
    /// зайвих рядків
    func testContentBodyJoinsDetailsAndWall() {
        XCTAssertEqual(
            ReminderScheduler.content(for: makeJob(details: "Розділ 3",
                                                   wallName: "Робота")).body,
            "Розділ 3\nРобота")
        XCTAssertEqual(
            ReminderScheduler.content(for: makeJob(wallName: "Робота")).body,
            "Робота")
        XCTAssertEqual(ReminderScheduler.content(for: makeJob()).body, "")
    }

    /// Звук, категорія з кнопками і лінк на стік для кліку — все на місці
    func testContentCarriesSoundCategoryAndStickerLink() {
        let job = makeJob()
        let content = ReminderScheduler.content(for: job)

        XCTAssertNotNil(content.sound)
        XCTAssertEqual(content.categoryIdentifier, ReminderScheduler.categoryID)
        XCTAssertEqual(content.userInfo["stickerID"] as? String, job.id.uuidString)
    }

    // MARK: - Кому ще можна нагадувати (кнопка «Відкласти»)

    /// Відкладати можна лише живий стік: банер міг провисіти довго, і за
    /// цей час стік устигали виконати чи видалити
    func testCanRemindOnlyLiveSticker() throws {
        let context = try makeContext()

        let live = makeSticker(in: context)
        XCTAssertTrue(ReminderScheduler.canRemind(live))

        let done = makeSticker(in: context)
        done.done = true
        XCTAssertFalse(ReminderScheduler.canRemind(done))

        let archived = makeSticker(in: context)
        archived.archived = true
        XCTAssertFalse(ReminderScheduler.canRemind(archived))

        let deleted = makeSticker(in: context)
        deleted.deletedAt = .now
        XCTAssertFalse(ReminderScheduler.canRemind(deleted))
    }

    /// Дедлайн, що вже минув, відкладенню не заважає — на відміну від
    /// планування: саме тому це окреме правило, а не job(for:)
    func testCanRemindIgnoresPastDeadline() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, deadlineIn: -3600)

        XCTAssertNil(ReminderScheduler.job(for: sticker))
        XCTAssertTrue(ReminderScheduler.canRemind(sticker))
    }

    // MARK: - Прибирання сиріт (хвости тестових прогонів, 2026-08-20)

    /// Зайве = наша категорія + id поза дозволеним набором (або не UUID).
    /// Чужі категорії не чіпаємо ніколи
    func testStaleIdentifiersPicksOnlyOurOrphans() {
        let mine = UUID(), orphan = UUID()
        let items = [
            (id: mine.uuidString, category: ReminderScheduler.categoryID),
            (id: orphan.uuidString, category: ReminderScheduler.categoryID),
            (id: "не-uuid", category: ReminderScheduler.categoryID),
            (id: UUID().uuidString, category: "чужаКатегорія"),
        ]

        let stale = ReminderScheduler.staleIdentifiers(among: items,
                                                       keeping: [mine])

        XCTAssertEqual(Set(stale), [orphan.uuidString, "не-uuid"])
    }

    /// ❗ Пастка, через яку зникало «Відкласти на 10 хв» (ревʼю
    /// 2026-08-20): відкладене сповіщення завжди належить стіку з уже
    /// МИНУЛИМ дедлайном. Планувати йому нічого (`job(for:)` мовчить),
    /// але право чекати в черзі він зберігає — інакше обслуговування
    /// бази зносить відкладений банер при першому ж запуску
    func testStickerWithPastDeadlineStillMayHoldNotification() throws {
        let context = try makeContext()
        let sticker = makeSticker(in: context, deadlineIn: -3600)

        XCTAssertNil(ReminderScheduler.job(for: sticker),
                     "нового планувати нічого — час минув")
        XCTAssertTrue(ReminderScheduler.canRemind(sticker),
                      "але відкладене сповіщення має право дочекатись")
    }

    // MARK: - Лічильник перепланувань (ревʼю 2026-08-20)

    /// Кожне скасування старить попереднє завдання: воно побачить, що
    /// покоління змінилось, і нічого не поставить
    func testCancelInvalidatesEarlierToken() {
        let id = UUID()
        let first = ReminderScheduler.cancel(id: id)

        let second = ReminderScheduler.cancel(id: id)

        XCTAssertNotEqual(first, second, "старе завдання не має вважати себе свіжим")
        XCTAssertEqual(ReminderScheduler.generationToken(for: id), second)
    }

    /// ❗ Гонка, через яку падав процес: `replan` продовжується на пулі, а
    /// `cancel` кличуть і з головного потоку, і з фонових задач. Голий
    /// Dictionary тут або валить malloc, або тихо губить інкременти —
    /// тест ловить друге навіть без санітайзера.
    ///
    /// ❗ Саме `concurrentPerform`, а НЕ `withTaskGroup`: цей клас —
    /// `@MainActor`, а дочірні задачі групи успадковують його актор і
    /// виконуються по черзі. Перший варіант тесту був на групі й
    /// проходив навіть на зламаному коді, ще й під ThreadSanitizer
    /// (перевірено 2026-08-20) — гонки в ньому просто не було
    func testConcurrentCancelsKeepEveryIncrement() {
        let id = UUID()
        let start = ReminderScheduler.generationToken(for: id)
        let rounds = 2_000

        DispatchQueue.concurrentPerform(iterations: rounds) { i in
            // Половина пише, половина читає: саме читання під час запису
            // й ламало памʼять
            if i.isMultiple(of: 2) {
                ReminderScheduler.cancel(id: id)
            } else {
                _ = ReminderScheduler.generationToken(for: id)
            }
        }

        XCTAssertEqual(ReminderScheduler.generationToken(for: id),
                       start + rounds / 2,
                       "жоден інкремент не має загубитись")
    }

    /// Різні стіки не заважають одне одному
    func testGenerationIsPerSticker() {
        let a = UUID(), b = UUID()
        ReminderScheduler.cancel(id: a)
        ReminderScheduler.cancel(id: a)
        let bToken = ReminderScheduler.cancel(id: b)

        XCTAssertEqual(bToken, ReminderScheduler.generationToken(for: b))
        XCTAssertNotEqual(ReminderScheduler.generationToken(for: a), bToken)
    }
}
