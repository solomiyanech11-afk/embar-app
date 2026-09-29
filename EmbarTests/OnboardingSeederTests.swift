//
//  OnboardingSeederTests.swift
//  EmbarTests
//
//  Навчальні стіки сідають ЛИШЕ в порожню стіну (рішення 2026-08-07):
//  новачок отримує туторіал, людина з наявними даними — ні. Помилка тут
//  означала б чотири чужі картки посеред справжніх записів, тому умову
//  перевіряємо з усіх боків: порожня стіна, непорожня, і стіна, де
//  лишились самі видалені стіки.
//

import XCTest
import SwiftData
@testable import Embar

@MainActor
final class OnboardingSeederTests: XCTestCase {

    private let seededIDsKey = "onboardingSeededStickerIDs"
    private var savedSeeded: Bool = false
    private var savedNote: Bool = false
    private var savedNotebook: Bool = false
    private var savedIDs: [String]?

    override func setUp() {
        super.setUp()
        // Прапорці живуть у справжніх налаштуваннях — зберігаємо й повертаємо
        savedSeeded = OnboardingStore.stickersSeeded
        savedNote = OnboardingStore.noteSeeded
        savedNotebook = OnboardingStore.notebookSeeded
        savedIDs = EmbarDefaults.store.stringArray(forKey: seededIDsKey)
        OnboardingStore.stickersSeeded = false
        OnboardingStore.noteSeeded = false
        OnboardingStore.notebookSeeded = false
        EmbarDefaults.store.removeObject(forKey: seededIDsKey)
        OnboardingSeeder.resetLaunchStateForTesting()
    }

    override func tearDown() {
        OnboardingStore.stickersSeeded = savedSeeded
        OnboardingStore.noteSeeded = savedNote
        OnboardingStore.notebookSeeded = savedNotebook
        if let savedIDs {
            EmbarDefaults.store.set(savedIDs, forKey: seededIDsKey)
        } else {
            EmbarDefaults.store.removeObject(forKey: seededIDsKey)
        }
        OnboardingSeeder.resetLaunchStateForTesting()
        container = nil
        super.tearDown()
    }

    /// ❗ Контейнер тримаємо у властивості, а не в локальній змінній:
    /// якщо він звільниться, його mainContext лишиться висіти в повітрі
    /// і будь-який fetch валить SwiftData (SIGTRAP, 2026-08-07)
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(schema: EmbarApp.schema,
                                               isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    private func liveCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Sticker>(
            predicate: #Predicate { $0.deletedAt == nil }))
    }

    // MARK: - Порожня стіна: туторіал потрібен

    func testSeedsIntoEmptyWall() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 6)
        XCTAssertTrue(OnboardingStore.stickersSeeded)
        XCTAssertTrue(OnboardingSeeder.didSeedThisLaunch)
    }

    /// Уроки мають читатись згори вниз — стіна сортує від новіших
    func testSeededOrderReadsTopDown() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let stickers = try context.fetch(FetchDescriptor<Sticker>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        XCTAssertEqual(stickers.map(\.text), OnboardingSeeder.lessons.map(\.text),
                       "уроки мусять читатись згори вниз у порядку списку")
    }

    // MARK: - Непорожня стіна: туторіал не потрібен

    func testSkipsWhenWallHasStickers() throws {
        let context = try makeContext()
        context.insert(Sticker(text: "Мій власний стік"))
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 1, "чужих карток на стіні не зʼявилось")
        XCTAssertFalse(OnboardingSeeder.didSeedStickersThisLaunch)
        XCTAssertTrue(OnboardingStore.stickersSeeded,
                      "рішення прийнято назавжди — пізніше стіки не зʼявляться")
    }

    /// Виконані й заархівовані теж означають «людина вже користувалась»
    func testSkipsWhenOnlyDoneOrArchivedStickersExist() throws {
        let context = try makeContext()
        let done = Sticker(text: "Зроблено")
        done.done = true
        let archived = Sticker(text: "В архіві")
        archived.archived = true
        context.insert(done)
        context.insert(archived)
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 2)
        XCTAssertFalse(OnboardingSeeder.didSeedStickersThisLaunch)
    }

    /// Видалені стіки стіну не «займають» — вона порожня, туторіал доречний
    func testSoftDeletedStickersDoNotBlockSeeding() throws {
        let context = try makeContext()
        let trashed = Sticker(text: "Давно видалений")
        trashed.deletedAt = .now
        context.insert(trashed)
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 6)
        XCTAssertTrue(OnboardingSeeder.didSeedThisLaunch)
    }

    /// Пʼятий стік двоповерховий: заголовок + деталі в розгорнутому вигляді
    func testFifthStickerHasBody() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let stickers = try context.fetch(FetchDescriptor<Sticker>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let withBody = stickers.filter { !$0.bodyText.isEmpty }
        XCTAssertEqual(withBody.count, 1, "тіло має бути рівно в одного стіка")
        XCTAssertEqual(withBody.first?.text, OnboardingSeeder.lessons[4].text)
    }

    // MARK: - Навчальна нотатка

    func testSeedsNoteIntoEmptyNotes() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, OnboardingSeeder.noteTitle)
        XCTAssertFalse(notes.first?.content.isEmpty ?? true)
        XCTAssertTrue(OnboardingStore.noteSeeded)
    }

    func testSkipsNoteWhenNotesExist() throws {
        let context = try makeContext()
        context.insert(Note(title: "Моя нотатка"))
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(notes.count, 1, "чужа нотатка не зʼявилась")
        XCTAssertEqual(notes.first?.title, "Моя нотатка")
        XCTAssertTrue(OnboardingStore.noteSeeded, "рішення прийнято назавжди")
    }

    // MARK: - Навчальний блокнот

    func testSeedsNotebookIntoEmptyShelf() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<ReaderBook>())
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.title, OnboardingSeeder.notebookTitle)

        // Стрічка блокнота показує новіші зверху, тож перший урок —
        // наймолодший: інакше новачок прочитав би уроки навпаки
        let entries = try context.fetch(FetchDescriptor<ReaderEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        XCTAssertEqual(entries.map(\.text), OnboardingSeeder.notebookEntries.map(\.text),
                       "записи мусять читатись згори вниз у порядку документа")
        XCTAssertEqual(entries.count, 6, "урок про кнопки розділено на три записи")
        XCTAssertEqual(entries.filter { $0.kind == .quote }.count, 1)
        // Тег мусить жити в записі БЕЗ хайлайта: у записі з підсвіткою
        // теги малюються плейн-текстом і капсулою не стають
        let tagEntry = try XCTUnwrap(entries.first { $0.text.contains("#embar") })
        XCTAssertTrue((tagEntry.highlights ?? []).isEmpty,
                      "запис із тегом не має містити хайлайтів")
        XCTAssertEqual(entries.first(where: { $0.kind == .quote })?.author, "Embar")
    }

    /// Слова «ось так» мусять бути реально підсвічені — інакше запис
    /// розповідає про хайлайти, не показуючи жодного
    func testNotebookHighlightLandsOnPhrase() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let marks = try context.fetch(FetchDescriptor<Highlight>())
        XCTAssertEqual(marks.count, 1)
        guard let mark = marks.first, let entry = mark.entry else {
            return XCTFail("хайлайт не привʼязаний до запису")
        }
        XCTAssertEqual(mark.colorName, "yellow")
        let ns = entry.text as NSString
        XCTAssertTrue(mark.start >= 0 && mark.end <= ns.length,
                      "діапазон мусить лежати в межах тексту")
        let phrase = ns.substring(with: NSRange(location: mark.start,
                                                length: mark.end - mark.start))
        XCTAssertFalse(phrase.isEmpty)
        XCTAssertTrue(entry.text.contains(phrase))
    }

    /// До запису про кнопки причеплена смужка з тими самими іконками
    func testIconStripIsAttached() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let withPhoto = try context.fetch(FetchDescriptor<ReaderEntry>())
            .filter { $0.photoData != nil }
        XCTAssertEqual(withPhoto.count, 1, "смужка має бути рівно в одного запису")
        let data = try XCTUnwrap(withPhoto.first?.photoData)
        XCTAssertNotNil(NSImage(data: data))
    }

    /// На обкладинці навчального блокнота — наш знак
    func testNotebookHasLogoCover() throws {
        let context = try makeContext()
        OnboardingSeeder.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<ReaderBook>())
        let data = try XCTUnwrap(books.first?.photoData)
        XCTAssertGreaterThan(data.count, 1000, "обкладинка мусить бути справжнім PNG")
        XCTAssertNotNil(NSImage(data: data))
    }

    func testSkipsNotebookWhenShelfNotEmpty() throws {
        let context = try makeContext()
        context.insert(ReaderBook(title: "Мій блокнот"))
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        let books = try context.fetch(FetchDescriptor<ReaderBook>())
        XCTAssertEqual(books.count, 1, "чужий блокнот не зʼявився")
        XCTAssertEqual(books.first?.title, "Мій блокнот")
        XCTAssertTrue(OnboardingStore.notebookSeeded)
    }

    /// Три сіячі незалежні: порожня стіна при наявних нотатках усе одно
    /// отримує стіки
    func testSeedersAreIndependent() throws {
        let context = try makeContext()
        context.insert(Note(title: "Моя нотатка"))
        try context.save()

        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 6, "стіки сіються попри нотатки")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReaderBook>()).count, 1)
    }

    // MARK: - Одноразовість

    func testDoesNothingWhenAlreadySeeded() throws {
        let context = try makeContext()
        OnboardingStore.stickersSeeded = true
        OnboardingStore.noteSeeded = true
        OnboardingStore.notebookSeeded = true

        OnboardingSeeder.seedIfNeeded(in: context)

        XCTAssertEqual(try liveCount(context), 0)
        XCTAssertFalse(OnboardingSeeder.didSeedThisLaunch)
    }
}

// MARK: - Форматування навчальної нотатки
//
// Тіло збирається прогоном крізь NoteFormatter, тож перевіряємо не
// «текст співпав», а що атрибути реально лягли: інакше нотатка
// приїхала б до людини плоскою, і це помітили б лише очима

@MainActor
final class TutorialNoteFormattingTests: XCTestCase {

    private var body: NSAttributedString { OnboardingSeeder.noteBodyAttributed() }

    private func attributes(of text: String) -> [NSAttributedString.Key: Any]? {
        let ns = body.string as NSString
        let range = ns.range(of: text)
        guard range.location != NSNotFound else { return nil }
        return body.attributes(at: range.location, effectiveRange: nil)
    }

    func testFirstLineIsPurpleHighlight() throws {
        let attrs = try XCTUnwrap(attributes(of: OnboardingSeeder.noteLines[0].text))
        XCTAssertEqual(attrs[.embarHighlight] as? String, HighlightColor.purple.rawValue)
    }

    func testHeadingIsBold() throws {
        let heading = OnboardingSeeder.noteLines.first { $0.bold }!
        let attrs = try XCTUnwrap(attributes(of: heading.text))
        XCTAssertEqual(attrs[.embarBold] as? NSNumber, true)
    }

    func testBulletsAndArrowMarkersAreInText() {
        let text = body.string
        XCTAssertEqual(text.filter { $0 == "•" }.count, 3, "три пункти з крапкою")
        XCTAssertEqual(text.filter { $0 == "→" }.count, 1, "пункт «Фото» - зі стрілкою")
    }

    func testListParagraphsCarryStyle() throws {
        for line in OnboardingSeeder.noteLines where line.list != nil {
            let attrs = try XCTUnwrap(attributes(of: line.text), line.text)
            XCTAssertEqual(attrs[.embarList] as? String, line.list?.rawValue, line.text)
        }
    }

    func testQuoteLineIsQuote() throws {
        let quote = OnboardingSeeder.noteLines.first { $0.quote }!
        let attrs = try XCTUnwrap(attributes(of: quote.text))
        XCTAssertEqual(attrs[.embarQuote] as? NSNumber, true)
    }

    /// «Папки:» курсивом, а решта пункту - ні
    func testItalicPrefixOnlyCoversPrefix() throws {
        let line = OnboardingSeeder.noteLines.first { $0.italicPrefix != nil }!
        let prefix = try XCTUnwrap(line.italicPrefix)
        let prefixAttrs = try XCTUnwrap(attributes(of: prefix))
        XCTAssertEqual(prefixAttrs[.embarItalic] as? NSNumber, true)

        let ns = body.string as NSString
        let rest = ns.range(of: line.text)
        let tail = NSRange(location: rest.location + (prefix as NSString).length + 1,
                           length: 1)
        let tailAttrs = body.attributes(at: tail.location, effectiveRange: nil)
        XCTAssertNil(tailAttrs[.embarItalic], "решта пункту курсивом бути не має")
    }

    func testFootnoteIsSmallAndItalic() throws {
        let note = OnboardingSeeder.noteLines.first { $0.role == .s }!
        let attrs = try XCTUnwrap(attributes(of: note.text))
        XCTAssertEqual(attrs[.embarRole] as? String, ParagraphRole.s.rawValue)
        XCTAssertEqual(attrs[.embarItalic] as? NSNumber, true)
    }

    /// Архів має пережити коло «закодувати - розкодувати»: саме в такому
    /// вигляді нотатка лягає в базу
    func testSurvivesArchiveRoundTrip() throws {
        let data = try XCTUnwrap(NoteArchiver.encode(body))
        let back = try XCTUnwrap(NoteArchiver.decode(data))
        XCTAssertEqual(back.string, body.string)
        let range = (back.string as NSString).range(of: OnboardingSeeder.noteLines[0].text)
        let attrs = back.attributes(at: range.location, effectiveRange: nil)
        XCTAssertEqual(attrs[.embarHighlight] as? String, HighlightColor.purple.rawValue)
    }
}

// MARK: - Міграція наявних користувачів (ревʼю 2026-08-12 №2)

@MainActor
final class OnboardingMigrationTests: XCTestCase {

    private var saved: (Bool, Bool, Bool, Bool) = (false, false, false, false)
    private var container: ModelContainer?

    override func setUp() {
        super.setUp()
        saved = (OnboardingStore.isCompleted, OnboardingStore.stickersSeeded,
                 OnboardingStore.noteSeeded, OnboardingStore.notebookSeeded)
        OnboardingStore.isCompleted = false
        OnboardingStore.stickersSeeded = false
        OnboardingStore.noteSeeded = false
        OnboardingStore.notebookSeeded = false
    }

    override func tearDown() {
        (OnboardingStore.isCompleted, OnboardingStore.stickersSeeded,
         OnboardingStore.noteSeeded, OnboardingStore.notebookSeeded) = saved
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let c = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(schema: EmbarApp.schema,
                                               isStoredInMemoryOnly: true))
        container = c
        return c.mainContext
    }

    /// Користувач з даними оновився: знайомство НЕ показується
    func testExistingUserSkipsOnboarding() throws {
        let context = try makeContext()
        context.insert(Sticker(text: "мій стік"))
        try context.save()

        OnboardingStore.migrateExistingUserIfNeeded(
            hasAnyUserData: OnboardingSeeder.hasAnyUserData(in: context))

        XCTAssertFalse(OnboardingStore.shouldRun)
        XCTAssertTrue(OnboardingStore.stickersSeeded, "і сіяч не сіятиме")
    }

    /// Дані - це й нотатки, і блокноти, не лише стіки
    func testNotesOrBooksCountAsData() throws {
        let context = try makeContext()
        context.insert(Note(title: "моя нотатка"))
        try context.save()
        XCTAssertTrue(OnboardingSeeder.hasAnyUserData(in: context))
    }

    /// Чистий перший запуск: міграція нічого не чіпає
    func testFreshUserStillGetsOnboarding() throws {
        let context = try makeContext()
        OnboardingStore.migrateExistingUserIfNeeded(
            hasAnyUserData: OnboardingSeeder.hasAnyUserData(in: context))
        XCTAssertTrue(OnboardingStore.shouldRun)
        XCTAssertFalse(OnboardingStore.stickersSeeded)
    }

    /// Той, хто ВЖЕ пройшов знайомство, міграцією не чіпається
    func testCompletedUserUntouched() throws {
        let context = try makeContext()
        OnboardingStore.isCompleted = true
        OnboardingStore.migrateExistingUserIfNeeded(
            hasAnyUserData: OnboardingSeeder.hasAnyUserData(in: context))
        XCTAssertFalse(OnboardingStore.stickersSeeded,
                       "порожні сіячі лишаються порожніми - сіяч сам вирішить")
    }
}

// MARK: - Пересів після дебаг-скидання (ревʼю 2026-08-12 №9)

@MainActor
final class OnboardingReseedTests: XCTestCase {

    private let idsKey = "onboardingSeededStickerIDs"
    private var saved: (Bool, [String]?) = (false, nil)
    private var container: ModelContainer?

    override func setUp() {
        super.setUp()
        saved = (OnboardingStore.stickersSeeded,
                 EmbarDefaults.store.stringArray(forKey: idsKey))
        OnboardingSeeder.resetLaunchStateForTesting()
    }

    override func tearDown() {
        OnboardingStore.stickersSeeded = saved.0
        if let ids = saved.1 { EmbarDefaults.store.set(ids, forKey: idsKey) }
        else { EmbarDefaults.store.removeObject(forKey: idsKey) }
        OnboardingSeeder.resetLaunchStateForTesting()
        container = nil
        super.tearDown()
    }

    /// Скидання на стіні, де лежав ЛИШЕ старий комплект: старий зникає,
    /// новий сідає. Раніше fetchCount міг побачити щойно видалені
    /// (незбережені) рядки, визнати стіну непорожньою і вимкнути пересів
    /// назавжди - людина лишалась із порожньою стіною
    func testResetReseedsWhenWallHadOnlyTutorial() throws {
        let c = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(schema: EmbarApp.schema,
                                               isStoredInMemoryOnly: true))
        container = c
        let context = c.mainContext

        // Перший посів
        OnboardingStore.stickersSeeded = false
        EmbarDefaults.store.removeObject(forKey: idsKey)
        OnboardingSeeder.seedIfNeeded(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Sticker>()),
                       OnboardingSeeder.lessons.count)

        // Дебаг-скидання прапорця (як -ResetOnboarding у пісочниці)
        OnboardingStore.stickersSeeded = false
        OnboardingSeeder.resetLaunchStateForTesting()
        OnboardingSeeder.seedIfNeeded(in: context)

        let all = try context.fetch(FetchDescriptor<Sticker>())
        XCTAssertEqual(all.count, OnboardingSeeder.lessons.count,
                       "рівно один свіжий комплект, без копій і без порожнечі")
        XCTAssertTrue(OnboardingSeeder.didSeedStickersThisLaunch,
                      "пересів мусив статися")
    }
}
