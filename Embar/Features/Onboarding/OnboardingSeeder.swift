//
//  OnboardingSeeder.swift
//  Embar
//
//  Навчальний контент першого запуску: 6 стіків на стіну, одна нотатка
//  і один блокнот Рідера. Тексти — з embar-texts-final.md.
//
//  Три ПРАВИЛА, спільні для всіх трьох сіячів:
//
//  1. Це ЗВИЧАЙНІ обʼєкти — не окрема сутність і не «системні». Їх
//     видаляють, виконують, редагують як усі інші; зникнувши, вони не
//     повертаються.
//  2. Кожен сіяч має ВЛАСНИЙ прапорець і сіє рівно один раз за життя
//     застосунку — тож повторний показ знайомства з Settings нічого не
//     пересіює.
//  3. Сіємо ЛИШЕ в порожнє: стіки — коли на стіні немає жодного живого
//     стіка, нотатку — коли немає жодної нотатки, блокнот — коли порожня
//     полиця. Туторіал потрібен новачкові; людині з наявними даними він
//     нічого не пояснює, а чужі картки серед її записів просто заважають.
//
//  Тексти пишемо мовою, яка активна в момент посіву — далі це вже дані
//  користувача, і перекладу вони не підлягають (той самий принцип, що
//  в текстах нагадувань).
//

import AppKit
import Foundation
import SwiftData
import SwiftUI // NSColor(EmbarColors.brandRed) — бренд-токени це SwiftUI.Color

@MainActor
enum OnboardingSeeder {

    // MARK: - Спільне

    /// Чи цей запуск засіяв ХОЧ ЩОСЬ
    private(set) static var didSeedThisLaunch = false

    /// Чи засіялись саме СТІКИ. Окремий прапорець, бо фінальний такт
    /// знайомства обіцяє стіки на стіні: у людини з непорожньою стіною,
    /// але порожніми нотатками, посів стається — а обіцяти стіки не можна
    private(set) static var didSeedStickersThisLaunch = false

    /// Лише для тестів: забути, що посів уже стався в цьому процесі
    static func resetLaunchStateForTesting() {
        didSeedThisLaunch = false
        didSeedStickersThisLaunch = false
    }

    /// Чи є в базі ХОЧ ЩОСЬ, створене людиною: живий стік, нотатка чи
    /// блокнот. Мірило міграції onboardingCompleted - помилка в бік
    /// «пропустити знайомство» дешевша за примусове знайомство для
    /// користувача з даними
    static func hasAnyUserData(in context: ModelContext) -> Bool {
        hasLiveStickers(in: context) || hasLiveNotes(in: context)
            || hasLiveBooks(in: context)
    }

    /// Викликати один раз при старті — кожен сіяч сам вирішує, чи його час
    static func seedIfNeeded(in context: ModelContext) {
        seedStickers(in: context)
        seedNote(in: context)
        seedNotebook(in: context)
    }

    // MARK: - Стіки

    /// id засіяних стіків — потрібні лише дебаг-скиданню, щоб повторний
    /// прогін онбордингу не накладав другий комплект на перший
    private static let seededIDsKey = "onboardingSeededStickerIDs"

    /// Урок: заголовок і (для пʼятого) додатковий текст у розгорнутому
    /// стіку. Не private — тест звіряє порядок посіву саме з цим списком,
    /// а не з підрядками: мова застосунку в тестах може бути будь-яка
    struct Lesson {
        let text: String
        var body: String = ""
    }

    static var lessons: [Lesson] {
        [
            Lesson(text: String(localized: "Це стік. Пиши сюди будь-що, щоб не загубити.")),
            Lesson(text: String(localized: "Затисни мене і потягни за край панелі. Залишусь на робочому столі.")),
            Lesson(text: String(localized: "Натисни ✓, коли зробиш. Стік опуститься вниз, а потім архівується (Строк є у налаштуваннях стіни внизу)")),
            Lesson(text: String(localized: "Вище є Нотатки й Рідер для довших думок. Заглянь, як матимеш час.")),
            Lesson(text: String(localized: "Натисни на мене. Можна додати більше тексту, дедлайн, папку і так далі."),
                   body: String(localized: "Тут можна дописати деталі до заголовка.\nЧіпи на картці: Дедлайн (усередині календар і нагадування) і Стіна (моя папка).\nПанель під карткою: пін закріплює зверху, смайлик чіпляє емоджі-тег, документ перетворює мене на нотатку, смітник видаляє.\nКоли стік позначений як виконаний, він піде в архів (строк можна змінити у налаштуваннях).")),
            Lesson(text: String(localized: "Кастомізуй усе. Налаштування стіни стіків внизу, загальні вгорі. Там же й hidden gems, палітри і багато цікавого.")),
        ]
    }

    private static func seedStickers(in context: ModelContext) {
        guard !OnboardingStore.stickersSeeded else { return }
        // Прапорець скинутий, а id з минулого посіву лишились — це
        // дебаг-прогін (-ResetOnboarding YES). Приберемо старий комплект,
        // щоб стіна не обростала копіями — і аж тоді дивимось, чи порожньо
        removeSeeded(in: context)
        // ❗ Зберегти ДО перевірки порожнечі: hasLiveStickers рахує через
        // fetchCount, а той може ще бачити щойно видалені (незбережені)
        // рядки - і тоді «непорожня» стіна навічно вимкнула б пересів
        // (ревʼю 2026-08-12 №9). Save робить стан однозначним
        try? context.save()

        guard !hasLiveStickers(in: context) else {
            // Рішення приймається один раз і назавжди, інакше стіки могли
            // б несподівано зʼявитись пізніше, коли людина все повидаляє
            OnboardingStore.stickersSeeded = true
            return
        }

        let now = Date.now
        var ids: [String] = []
        for (i, lesson) in lessons.enumerated() {
            let sticker = Sticker(text: lesson.text, colorIndex: i % 5)
            sticker.bodyText = lesson.body
            // Стіна сортує від новіших до старіших — щоб уроки читались
            // згори вниз, перший має бути наймолодшим
            sticker.createdAt = now.addingTimeInterval(-Double(i))
            sticker.updatedAt = sticker.createdAt
            context.insert(sticker)
            ids.append(sticker.id.uuidString)
        }
        try? context.save()
        StickerMutation.bulkChanged() // кеш зрізу: пачка нових стіків (F5)
        EmbarDefaults.store.set(ids, forKey: seededIDsKey)
        OnboardingStore.stickersSeeded = true
        didSeedThisLaunch = true
        didSeedStickersThisLaunch = true
    }

    /// id навчальних стіків - за ними стіна знає, які з її карток
    /// туторіальні (кнопка «прибрати навчальні стіки»)
    static var seededStickerIDs: Set<UUID> {
        Set((EmbarDefaults.store.stringArray(forKey: seededIDsKey) ?? [])
            .compactMap(UUID.init(uuidString:)))
    }

    /// Чи є на стіні хоч один живий стік. Живий = не видалений; виконані
    /// й заархівовані рахуються теж — вони так само означають, що людина
    /// застосунком уже користувалась
    static func hasLiveStickers(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Sticker>(
            predicate: #Predicate { $0.deletedAt == nil })
        // Не змогли прочитати стіну — вважаємо, що дані є: краще не
        // засіяти туторіал, ніж вкинути картки поверх чужих записів
        guard let count = try? context.fetchCount(descriptor) else { return true }
        return count > 0
    }

    /// Фізичне видалення попереднього посіву — свідомий виняток із
    /// правила «ніколи не видаляти дані користувача назавжди»: це наші
    /// власні стіки і тільки в дебаг-сценарії (той самий виклик робить
    /// «скинути онбординг» у пульті пісочниці)
    static func removeSeeded(in context: ModelContext) {
        let stored = EmbarDefaults.store.stringArray(forKey: seededIDsKey) ?? []
        guard !stored.isEmpty else { return }
        let ids = Set(stored.compactMap(UUID.init(uuidString:)))
        if let all = try? context.fetch(FetchDescriptor<Sticker>()) {
            for sticker in all where ids.contains(sticker.id) {
                context.delete(sticker)
            }
        }
        EmbarDefaults.store.removeObject(forKey: seededIDsKey)
        StickerMutation.bulkChanged() // кеш зрізу: hard delete пачки (F5)
        NoteMutation.bulkChanged()
    }

    // MARK: - Навчальна нотатка

    static var noteTitle: String {
        String(localized: "Це нотатка")
    }

    /// Рядок навчальної нотатки: текст плюс те, чим він оформлений.
    /// `italicPrefix` - початок рядка, що йде курсивом («Папки:»)
    struct NoteLine {
        let text: String
        var role: ParagraphRole = .p
        var list: ListStyle? = nil
        var quote: Bool = false
        var bold: Bool = false
        var italic: Bool = false
        var highlight: HighlightColor? = nil
        var italicPrefix: String? = nil
    }

    static var noteLines: [NoteLine] {
        [
            NoteLine(text: String(localized: "Нотатки для думок, які довші за стік."),
                     highlight: .purple),
            NoteLine(text: ""),
            NoteLine(text: String(localized: "Що тут є:"), bold: true),
            NoteLine(text: String(localized: "Папки: кнопка «Папки» зверху."),
                     list: .bullet,
                     italicPrefix: String(localized: "Папки:", comment: "Курсивний початок пункту в навчальній нотатці")),
            NoteLine(text: String(localized: "Пін: закріпити важливу нотатку зверху."),
                     list: .bullet,
                     italicPrefix: String(localized: "Пін:", comment: "Курсивний початок пункту в навчальній нотатці")),
            NoteLine(text: String(localized: "Колір: акцент картки, колір тексту й маркер."),
                     list: .bullet,
                     italicPrefix: String(localized: "Колір:", comment: "Курсивний початок пункту в навчальній нотатці")),
            NoteLine(text: String(localized: "Фото: прикріплюй прямо в текст."),
                     list: .arrow,
                     italicPrefix: String(localized: "Фото:", comment: "Курсивний початок пункту в навчальній нотатці")),
            NoteLine(text: String(localized: "Цитати: виділяються рискою зліва, гарно тримають чуже слово."),
                     quote: true),
            NoteLine(text: ""),
            NoteLine(text: String(localized: "Головний трюк: напиши [[ і вибери іншу нотатку. Зʼявиться звʼязок, і внизу тієї нотатки буде видно, хто її згадує. Так думки повʼязуються між собою.")),
            NoteLine(text: ""),
            NoteLine(text: String(localized: "Стік теж вміє ставати нотаткою: кнопка з документом у відкритому стіку.")),
            NoteLine(text: String(localized: "*Ця нотатка звичайна, видали її, коли прочитаєш."),
                     role: .s, italic: true),
        ]
    }

    /// Тіло навчальної нотатки з форматуванням.
    ///
    /// ❗ Збираємо НЕ атрибутами руками, а прогоном крізь NoteFormatter на
    /// невидимому NSTextView - тим самим шляхом, яким форматує сам
    /// редактор. Інакше маркери списків, відступи й ролі абзаців легко
    /// розійшлися б із тим, що редактор вважає правильним, і нотатка
    /// поводилась би дивно при першому ж редагуванні.
    static func noteBodyAttributed() -> NSAttributedString {
        let settings = NoteDocSettings.default
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 4000))
        tv.string = noteLines.map(\.text).joined(separator: "\n")
        NoteFormatter.restyleDocument(tv, settings: settings)
        guard let storage = tv.textStorage else { return NSAttributedString(string: tv.string) }

        // Спершу абзацне оформлення: списки вставляють у текст маркери,
        // тож усі подальші діапазони шукаємо ВЖЕ по новому рядку
        for line in noteLines where line.list != nil || line.quote || line.role != .p {
            guard let range = paragraphRange(of: line.text, in: storage) else { continue }
            tv.setSelectedRange(range)
            if let list = line.list {
                NoteFormatter.toggleList(list, in: tv, settings: settings)
            }
            if line.quote {
                NoteFormatter.toggleQuote(tv, settings: settings)
            }
            if line.role != .p {
                NoteFormatter.setRole(line.role, in: tv, settings: settings)
            }
        }

        // Далі інлайн: жирний, курсив, хайлайт
        for line in noteLines {
            guard !line.text.isEmpty else { continue }
            guard let range = paragraphRange(of: line.text, in: storage) else { continue }
            if line.bold {
                tv.setSelectedRange(range)
                NoteFormatter.toggleBold(tv, settings: settings)
            }
            if line.italic {
                tv.setSelectedRange(range)
                NoteFormatter.toggleItalic(tv, settings: settings)
            }
            if let color = line.highlight {
                tv.setSelectedRange(range)
                NoteFormatter.toggleHighlight(color, in: tv)
            }
            if let prefix = line.italicPrefix {
                let sub = (storage.string as NSString).range(of: prefix, options: [],
                                                             range: range)
                if sub.location != NSNotFound {
                    tv.setSelectedRange(sub)
                    NoteFormatter.toggleItalic(tv, settings: settings)
                }
            }
        }
        return NSAttributedString(attributedString: storage)
    }

    /// Діапазон рядка ТІЛЬКИ з його текстом - без маркера списку, який
    /// рушій дописав на початок абзацу
    private static func paragraphRange(of text: String,
                                       in storage: NSTextStorage) -> NSRange? {
        let ns = storage.string as NSString
        let found = ns.range(of: text)
        return found.location == NSNotFound ? nil : found
    }

    private static func seedNote(in context: ModelContext) {
        guard !OnboardingStore.noteSeeded else { return }
        guard !hasLiveNotes(in: context) else {
            OnboardingStore.noteSeeded = true
            return
        }
        let body = noteBodyAttributed()
        let note = Note(title: noteTitle,
                        content: NoteArchiver.plainText(body))
        note.contentData = NoteArchiver.encode(body)
        note.contentVersion = 1
        // Фіолетовий акцент картки - слот 4 палітри (у Cream це
        // лавандовий #ede9fe). Слот, а не hex: при зміні палітри колір
        // їде разом з нею, як у решти акцентів
        note.accentColorIndex = 4
        context.insert(note)
        try? context.save()
        NoteMutation.changed(note) // кеш списку (F5.4): навчальна нотатка
        OnboardingStore.noteSeeded = true
        didSeedThisLaunch = true
    }

    static func hasLiveNotes(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil })
        guard let count = try? context.fetchCount(descriptor) else { return true }
        return count > 0
    }

    // MARK: - Навчальний блокнот Рідера

    static var notebookTitle: String {
        String(localized: "Як працює Рідер")
    }

    /// Записи блокнота в порядку написання. Автор — лише в цитати
    struct NotebookEntry {
        let kind: ReaderEntryKind
        let text: String
        var author: String? = nil
        /// Підрядок, який треба підсвітити жовтим. Шукаємо його в тексті
        /// на посіві, а не тримаємо індекси: вони різні в кожній мові
        var highlight: String? = nil
        /// Причепити до запису смужку з іконками композера
        var withIconStrip: Bool = false
    }

    static var notebookEntries: [NotebookEntry] {
        [
            NotebookEntry(kind: .thought,
                          text: String(localized: "Це запис-думка. Пиши сюди все, що спадає на думку, поки читаєш чи дивишся щось.")),
            NotebookEntry(kind: .quote,
                          text: String(localized: "А це цитата. У неї є поле автора і своя типографіка."),
                          author: "Embar"),
            NotebookEntry(kind: .thought,
                          text: String(localized: "Кнопка «Тема» зверху групує записи: увімкни тему, і все нове писатиметься під неї. Вимкни, коли розділ закінчився.")),
            // ⚠️ Запис із хайлайтом малюється через NSTextView, а там
            // #теги лишаються плейн-текстом. Тому урок розділено: тег
            // живе в записі БЕЗ підсвітки й стає справжньою капсулою
            NotebookEntry(kind: .thought,
                          text: String(localized: "Що тут ще є.\n\nУ полі вводу зверху: перо підсвічує виділений текст, камера чіпляє фото до запису, мікрофон записує голосову думку.\n\nПоруч - тип запису: Думка чи Цитата. Питання та Інсайт можна ввімкнути в налаштуваннях."),
                          highlight: String(localized: "перо підсвічує виділений текст", comment: "Слова, підсвічені жовтим у навчальному блокноті"),
                          // Замість іконок усередині тексту (їх туди не
                          // вставити - див. коментар до iconStripData)
                          // чіпляємо смужку з цими самими кнопками фото
                          // до запису. Заодно показує, що фото до запису
                          // взагалі бувають
                          withIconStrip: true),
            NotebookEntry(kind: .thought,
                          text: String(localized: "Серденько на записі кладе його в обране. Кнопка з документом перетворює запис на нотатку. А хештег у тексті стає тегом #embar")),
            NotebookEntry(kind: .thought,
                          text: String(localized: "Налаштування (повзунки внизу) міняють шрифт записів, хештеги, рядок джерела й додаткові типи.\n\nЦей блокнот звичайний: видали його, коли роздивишся.")),
        ]
    }

    private static func seedNotebook(in context: ModelContext) {
        guard !OnboardingStore.notebookSeeded else { return }
        guard !hasLiveBooks(in: context) else {
            OnboardingStore.notebookSeeded = true
            return
        }

        let book = ReaderBook(title: notebookTitle)
        book.photoData = logoCoverData()
        context.insert(book)
        let now = Date.now
        for (i, item) in notebookEntries.enumerated() {
            let entry = ReaderEntry(kind: item.kind, text: item.text)
            entry.author = item.author
            // ❗ Стрічка блокнота показує НОВІШІ ЗВЕРХУ (blocks.sort за
            // спаданням). Новачок читає згори вниз, тому перший урок має
            // бути наймолодшим — порядок такий самий, як на стіні стіків
            // (фідбек 2026-08-09: спершу уроки лежали навпаки)
            entry.createdAt = now.addingTimeInterval(-Double(i))
            entry.updatedAt = entry.createdAt
            if item.withIconStrip { entry.photoData = iconStripData() }
            entry.book = book
            context.insert(entry)

            // Хайлайт по знайденому підрядку. Не знайшли (переклад
            // розійшовся з фразою) — просто лишаємо запис без підсвітки
            if let phrase = item.highlight {
                let range = (item.text as NSString).range(of: phrase)
                if range.location != NSNotFound {
                    let mark = Highlight(start: range.location,
                                         end: range.location + range.length,
                                         colorName: "yellow", mode: "highlight")
                    mark.entry = entry
                    context.insert(mark)
                }
            }
        }
        book.updatedAt = now
        try? context.save()
        OnboardingStore.notebookSeeded = true
        didSeedThisLaunch = true
    }

    /// Смужка з іконками композера — перо, камера, мікрофон.
    ///
    /// Іконки НЕ вставляються в сам текст запису, і це не лінь:
    /// хайлайти адресуються індексами символів у тексті, а зображення-
    /// вкладення ці індекси зсунуло б — поламало б і наші підсвітки, і
    /// ті, що користувач уже поставив у своїх записах. Тому показуємо
    /// кнопки фотографією поруч із текстом
    static func iconStripData() -> Data? {
        let icons = ["pencil.line", "camera", "mic"]
        let width: CGFloat = 900, height: CGFloat = 240
        let iconSide: CGFloat = 96
        let config = NSImage.SymbolConfiguration(pointSize: iconSide, weight: .regular)

        let strip = NSImage(size: NSSize(width: width, height: height))
        strip.lockFocus()
        NSColor(embarHex: "#fcfbf9").setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (i, name) in icons.enumerated() {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { continue }
            let size = symbol.size
            // Тонуємо в окремому полотні: sourceAtop поверх готового
            // фону затонував би і фон теж
            let tinted = NSImage(size: size)
            tinted.lockFocus()
            symbol.draw(in: NSRect(origin: .zero, size: size))
            NSColor(embarHex: "#555555").set()
            NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
            tinted.unlockFocus()

            let slot = width / CGFloat(icons.count)
            let x = slot * (CGFloat(i) + 0.5) - size.width / 2
            tinted.draw(in: NSRect(x: x, y: (height - size.height) / 2,
                                   width: size.width, height: size.height))
        }
        strip.unlockFocus()

        guard let tiff = strip.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Обкладинка навчального блокнота — наш знак на мʼятному полі.
    /// Малюємо на місці, щоб не тягнути в бандл окремий PNG
    static func logoCoverData() -> Data? {
        guard let mark = NSImage(named: "logo-mark") else { return nil }
        let side: CGFloat = 640
        let markSide: CGFloat = 330

        // Знак — template-асет (чорний силует), тому спершу фарбуємо
        // його в ОКРЕМОМУ прозорому полотні: sourceAtop поверх готового
        // фону затонував би і фон теж
        let tinted = NSImage(size: NSSize(width: markSide, height: markSide))
        tinted.lockFocus()
        let markRect = NSRect(x: 0, y: 0, width: markSide, height: markSide)
        mark.draw(in: markRect)
        // Тут ми перемальовуємо САМЕ лого — тож і колір, і мʼятне тло
        // беремо з бренд-токенів, які дорівнюють оригіналу асета
        // (ревізія 2026-08-17: раніше стояли примірки #F93B3B / #E9F3F1,
        // і навчальна обкладинка виходила іншого відтінку, ніж знак)
        NSColor(EmbarColors.brandRed).set()
        markRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let cover = NSImage(size: NSSize(width: side, height: side))
        cover.lockFocus()
        NSColor(EmbarColors.brandMint).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        tinted.draw(in: NSRect(x: (side - markSide) / 2, y: (side - markSide) / 2,
                               width: markSide, height: markSide))
        cover.unlockFocus()

        guard let tiff = cover.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func hasLiveBooks(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ReaderBook>(
            predicate: #Predicate { $0.deletedAt == nil })
        guard let count = try? context.fetchCount(descriptor) else { return true }
        return count > 0
    }
}
