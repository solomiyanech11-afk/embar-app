#if DEBUG
//
//  DemoSeeder.swift
//  Embar
//
//  Демо-дані для маркетингових скріншотів (docs/DEMO-SEED-SPEC.md):
//  прапорець `-SandboxSeedDemo` у схемі «Embar (Sandbox)» сіє базу так,
//  ніби це програма реальної людини — студентки з персонажа специфікації.
//
//  Правила (ті самі, що в решти команд пісочниці):
//  · працює ЛИШЕ під SandboxEnvironment.isActive — реальна база
//    (default.store) і реальні налаштування недосяжні за визначенням:
//    усі записи йдуть у sandbox.store і суїт пісочниці;
//  · ідемпотентний: прапорець seededKey у суїті пісочниці; повторний
//    запуск нічого не дублює. `-SandboxWipe -SandboxSeedDemo` дає
//    чистий демо-стан (wipe зносить і суїт, і базу — прапорець зникає);
//  · усі дати ВІДНОСНІ до «зараз» (створення розкидане на останні
//    3 тижні, дедлайни в майбутньому), щоб демо не старіло;
//  · онбординг позначається пройденим, навчальний контент НЕ сіється;
//  · тексти — дослівно зі специфікації, без редагування.
//
//  Фото: сідер шукає файли за іменами зі специфікації спершу в бандлі
//  (тека Embar/Debug/DemoPhotos/ — синхронізована група кладе її вміст
//  у Resources), потім у контейнері пісочниці
//  (Application Support/EmbarTestSandbox/DemoPhotos/). Немає файлу —
//  запис сіється без фото, рядок-плейсхолдер [photo: …] не потрапляє
//  в тіло.
//  ⚠️ Файли з Embar/Debug/DemoPhotos/ потраплять і в Release-бандл
//  (синхронізовані групи не знають конфігурацій) — перед релізом тека
//  мусить бути порожньою.
//

import AppKit
import SwiftData

@MainActor
enum DemoSeeder {

    /// Прапорець «уже засіяно» в суїті пісочниці (ідемпотентність)
    static let seededKey = "sandboxDemoSeeded"

    // MARK: - Вхідна точка

    /// Засіяти демо-набір, якщо його ще немає. Повертає true, якщо посів
    /// відбувся цього виклику
    @discardableResult
    static func seedIfNeeded(in context: ModelContext) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        guard !EmbarDefaults.store.bool(forKey: seededKey) else {
            NSLog("Пісочниця: демо-набір уже засіяно — пропускаю")
            return false
        }
        applySettings()
        let walls = seedWalls(in: context)
        seedStickers(walls: walls, in: context)
        seedNotes(in: context)
        seedReader(in: context)
        try? context.save()
        EmbarDefaults.store.set(true, forKey: seededKey)
        StickerMutation.bulkChanged() // кеш зрізу: пачка нових стіків
        NoteMutation.bulkChanged()
        NSLog("Пісочниця: засіяно демо-набір для маркетингу (DEMO-SEED-SPEC)")
        return true
    }

    // MARK: - Налаштування для демо

    /// Онбординг пройдено (навчальний контент НЕ сіється — прапорці
    /// посіву теж зведені), мова English, автоархів місяць, тиждень у
    /// футері, рядок джерела і додаткові типи в Рідері, колір стіків —
    /// від стіни.
    ///
    /// ⚠️ Мова: у пісочниці запис AppleLanguages іде в суїт, а система
    /// при старті читає домен застосунку — тож сам по собі цей запис UI
    /// не перемкне. Для знімків англійською застосунок запускається з
    /// аргументом `-AppleLanguages "(en)"` (argument domain читається
    /// першим і працює всюди)
    private static func applySettings() {
        let defaults = EmbarDefaults.store
        OnboardingStore.isCompleted = true
        OnboardingStore.stickersSeeded = true
        OnboardingStore.noteSeeded = true
        OnboardingStore.notebookSeeded = true
        defaults.set(true, forKey: SettingsGlow.storageKey)
        LanguageStore.selected = .en
        defaults.set(30, forKey: StickyAutoArchive.storageKey)
        defaults.set(true, forKey: "showWeekStrip")
        defaults.set(true, forKey: "readerShowSourceLink")
        defaults.set(true, forKey: "readerExtraTypes")
        defaults.set("byWall", forKey: "wallColorMode")
    }

    // MARK: - Дати (усе відносне до «зараз»)

    private static var calendar: Calendar { Calendar.current }

    /// N днів тому о конкретній годині — час створення реалістичний,
    /// не 00:00
    private static func daysAgo(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Через N днів о конкретній годині (дедлайни в майбутньому)
    private static func inDays(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: .now) ?? .now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Найближчий МАЙБУТНІЙ день тижня (1 = неділя … 7 = субота)
    private static func next(weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.nextDate(after: .now,
                          matching: DateComponents(hour: hour, minute: minute,
                                                   weekday: weekday),
                          matchingPolicy: .nextTime) ?? inDays(1, hour, minute)
    }

    // MARK: - Стіни

    private struct DemoWalls {
        let uni: Wall
        let life: Wall
        let work: Wall
        let ideas: Wall
    }

    /// 4 стіни зі своїм кольором (слоти палітри Cream: 1 блакитний,
    /// 3 теплий рожево-персиковий, 2 зелений, 4 лавандовий)
    private static func seedWalls(in context: ModelContext) -> DemoWalls {
        func wall(_ name: String, slot: Int, order: Int) -> Wall {
            let w = Wall(name: name)
            w.colorSlot = slot
            w.sortOrder = order
            w.createdAt = daysAgo(21, 12)
            w.updatedAt = w.createdAt
            context.insert(w)
            return w
        }
        return DemoWalls(uni: wall("Uni", slot: 1, order: 0),
                         life: wall("Life", slot: 3, order: 1),
                         work: wall("Work", slot: 2, order: 2),
                         ideas: wall("Ideas", slot: 4, order: 3))
    }

    // MARK: - Стіки

    @discardableResult
    private static func sticky(_ text: String, _ body: String = "",
                               wall: Wall, created: Date,
                               deadline: Date? = nil, notify: Int? = nil,
                               pinned: Bool = false, emoji: String? = nil,
                               in context: ModelContext) -> Sticker {
        let s = Sticker(text: text, colorIndex: wall.effectiveColorSlot)
        s.bodyText = body
        s.wall = wall
        s.createdAt = created
        s.updatedAt = created
        s.deadline = deadline
        s.notifyOffsetMinutes = notify
        s.pinned = pinned
        s.emojiTag = emoji
        context.insert(s)
        return s
    }

    private static func seedStickers(walls: DemoWalls, in context: ModelContext) {
        // Активні (18)
        let essay = sticky("Essay draft: attention economy",
                           "Intro is done, need 2 more sources for the second part. Ask in the seminar if a podcast counts as a source.",
                           wall: walls.uni, created: daysAgo(2, 21, 40),
                           deadline: next(weekday: 5, 23, 59), notify: 60,
                           pinned: true, emoji: "📚", in: context)
        sticky("This week",
               "Thu essay draft, Fri shift 15–22, Sat Maya's birthday, Sun call grandma",
               wall: walls.life, created: daysAgo(1, 8, 15),
               pinned: true, in: context)
        sticky("Email Prof. Hart about the extension",
               "Be honest, say the group project ate the week.",
               wall: walls.uni, created: daysAgo(0, 9, 5),
               deadline: inDays(1, 12, 0), notify: 30, emoji: "📚", in: context)
        sticky("Return the black jacket",
               "Receipt is in the drawer, 30-day window ends on the 19th",
               wall: walls.life, created: daysAgo(3, 19, 30),
               deadline: inDays(6, 18, 0), emoji: "🏠", in: context)
        sticky("Library book due",
               "The Body Keeps the Score, renew online if not finished",
               wall: walls.uni, created: daysAgo(4, 16, 20),
               deadline: inDays(5, 12, 0), notify: 1440, in: context)
        sticky("Groceries",
               "oat milk, lemons, rice, batteries for the scale, that hot sauce Tom keeps talking about",
               wall: walls.life, created: daysAgo(0, 12, 45), emoji: "🏠", in: context)
        sticky("Ask Maya for her stats notes",
               "Week 4 and 5, I missed both",
               wall: walls.uni, created: daysAgo(5, 14, 10), in: context)
        sticky("Shift swap with Lena",
               "My Sat → her Sun, tell Marco by Wednesday",
               wall: walls.work, created: daysAgo(1, 15, 35),
               deadline: next(weekday: 4, 17, 0), emoji: "💼", in: context)
        sticky("Ask about the November schedule",
               "Want the 8th and 9th off for the trip",
               wall: walls.work, created: daysAgo(6, 11, 0), emoji: "💼", in: context)
        sticky("Call grandma",
               "Ask about the plov recipe, write it down this time",
               wall: walls.life, created: daysAgo(2, 20, 15),
               deadline: next(weekday: 1, 18, 0), notify: 0, emoji: "❤️", in: context)
        sticky("Birthday gift for Maya",
               "film camera? the vinyl she mentioned? something for the new flat?",
               wall: walls.life, created: daysAgo(7, 22, 30), emoji: "🎁", in: context)
        sticky("Renew student travel card",
               "Expires end of month, need a new photo",
               wall: walls.life, created: daysAgo(8, 10, 40),
               deadline: inDays(9, 12, 0), in: context)
        let water = sticky("Drink water, stretch, look away from the screen",
                           wall: walls.life, created: daysAgo(12, 9, 0),
                           emoji: "🌱", in: context)
        sticky("Thesis idea: how notification design shapes what we pay attention to",
               "Talk to Prof. Hart about whether this is too broad. Related to the essay.",
               wall: walls.ideas, created: daysAgo(9, 23, 10), emoji: "💡", in: context)
        sticky("Podcast with Ana",
               "20-minute episodes, one question each, no intro music",
               wall: walls.ideas, created: daysAgo(10, 21, 5), emoji: "💡", in: context)
        sticky("Learn to make risotto properly",
               "not the packet one",
               wall: walls.ideas, created: daysAgo(15, 19, 50), in: context)
        sticky("Dentist",
               "book before December, the left one hurts when cold",
               wall: walls.life, created: daysAgo(11, 8, 30), emoji: "🦷", in: context)
        sticky("Print the reading for Tuesday seminar",
               "40 pages, library printer is cheaper",
               wall: walls.uni, created: daysAgo(1, 18, 20),
               deadline: next(weekday: 3, 9, 0), in: context)

        // Один-два стіки одразу як віджети на столі — права нижня чверть
        // екрана. floatY — ВЕРХНІЙ край вікна (якір авто-висоти), розмір
        // nil = авто; позиція поза екраном виправиться клампом менеджера
        let vf = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1512, height: 944)
        essay.isFloating = true
        essay.floatX = vf.minX + vf.width * 0.60
        essay.floatY = vf.minY + vf.height * 0.44
        water.isFloating = true
        water.floatX = vf.minX + vf.width * 0.76
        water.floatY = vf.minY + vf.height * 0.26

        // Виконані (5) — у секції Done, різний час виконання за останні дні
        func done(_ text: String, wall: Wall, created: Date, doneAt: Date) {
            let s = sticky(text, wall: wall, created: created, in: context)
            s.done = true
            s.updatedAt = doneAt
            // Відлік автоархіву стартує з моменту виконання
            s.archiveCountdownAt = doneAt
        }
        done("Submit the housing form", wall: walls.uni,
             created: daysAgo(18, 10, 0), doneAt: daysAgo(1, 17, 0))
        done("Pay rent", wall: walls.life,
             created: daysAgo(16, 9, 30), doneAt: daysAgo(2, 8, 50))
        done("Reply to the Erasmus office", wall: walls.uni,
             created: daysAgo(14, 13, 0), doneAt: daysAgo(3, 12, 10))
        done("Buy a lamp for the desk", wall: walls.life,
             created: daysAgo(17, 20, 0), doneAt: daysAgo(4, 19, 0))
        done("Send Tom the photos from Saturday", wall: walls.life,
             created: daysAgo(12, 22, 0), doneAt: daysAgo(0, 21, 30))

        // Архів (2) — виконані понад строк, для показу архіву
        func archived(_ text: String, wall: Wall, created: Date, archivedAt: Date) {
            let s = sticky(text, wall: wall, created: created, in: context)
            s.done = true
            s.archived = true
            s.archivedAt = archivedAt
            s.archiveCountdownAt = created
            s.updatedAt = archivedAt
        }
        archived("Pick up the parcel", wall: walls.life,
                 created: daysAgo(21, 11, 20), archivedAt: daysAgo(3, 9, 0))
        archived("Register for the gym", wall: walls.life,
                 created: daysAgo(20, 18, 40), archivedAt: daysAgo(5, 9, 0))
    }

    // MARK: - Нотатки

    private static func seedNotes(in context: ModelContext) {
        func folder(_ name: String) -> NoteFolder {
            let f = NoteFolder(name: name)
            f.createdAt = daysAgo(20, 12)
            f.updatedAt = f.createdAt
            context.insert(f)
            return f
        }
        let uni = folder("Uni")
        let ideas = folder("Ideas")
        let journal = folder("Journal")
        let home = folder("Home")

        // Фаза 1: створити всі нотатки (чіпи [[ ]] у тілах посилаються
        // одна на одну — цілі мусять існувати до побудови тіл)
        func note(_ title: String, folder: NoteFolder, created: Date,
                  updated: Date? = nil, pinned: Bool = false,
                  tags: [String] = []) -> Note {
            let n = Note(title: title)
            n.folder = folder
            n.createdAt = created
            n.updatedAt = updated ?? created
            n.pinned = pinned
            n.tags = tags
            context.insert(n)
            return n
        }
        let essayPlan = note("Essay plan: the attention economy", folder: uni,
                             created: daysAgo(4, 20, 30),
                             updated: daysAgo(1, 22, 15),
                             pinned: true, tags: ["#essay"])
        let seneca = note("Reading notes: Seneca, On the Shortness of Life",
                          folder: uni, created: daysAgo(8, 22, 40))
        let thesis = note("Thesis idea: notifications and attention",
                          folder: ideas, created: daysAgo(6, 23, 20))
        let podcast = note("Podcast with Ana", folder: ideas,
                           created: daysAgo(10, 21, 10), tags: ["#someday"])
        let city = note("New city, month two", folder: journal,
                        created: daysAgo(5, 21, 50))
        let moving = note("Moving checklist, done version", folder: home,
                          created: daysAgo(13, 18, 30))
        let plov = note("Grandma's plov", folder: home,
                        created: daysAgo(9, 19, 40))
        let portfolio = note("Portfolio site notes", folder: ideas,
                             created: daysAgo(3, 16, 25))

        let byTitle = Dictionary(uniqueKeysWithValues:
            [essayPlan, seneca, thesis, podcast, city, moving, plov, portfolio]
                .map { ($0.title, $0) })

        // Фаза 2: тіла (тексти — дослівно зі специфікації)
        applyBody("""
        Question
        Why does it feel harder to focus now than it did five years ago, and how much of that is design?

        Structure
        • Intro: the feeling everyone recognises, then the claim that it is not just us
        • Part 1: what attention is, briefly (cognitive psych, week 6)
        • Part 2: how interfaces are built to capture it (notifications, infinite scroll, variable rewards)
        • Part 3: what changes when you design for the opposite
        • Conclusion: attention as something you can protect, not only lose

        Sources so far
        1. [[Reading notes: Seneca, On the Shortness of Life]]
        2. Lecture notes, week 6 (in Reader)
        3. Need two more. Ask if a podcast counts.

        > It is not that we have a short time to live, but that we waste a lot of it.
        > Seneca

        Deadline Thursday. Draft first, polish never.
        """, to: essayPlan, notesByTitle: byTitle, in: context)

        applyBody("""
        Read it in two evenings. Surprisingly modern.

        > Life is long, if you know how to use it.
        > Seneca

        Main idea: people guard their money and give away their time for free. The whole essay is about that one asymmetry.

        What I want to use in the essay: the idea that busyness is a way of not living. Ties directly to the notification argument in [[Essay plan: the attention economy]].

        Things I underlined
        • "You act like mortals in all that you fear, and like immortals in all that you desire."
        • The part about people planning for a life they never start.
        """, to: seneca, notesByTitle: byTitle, in: context)

        applyBody("""
        Still too broad. Possible narrowings:
        • Only lock screen notifications
        • Only one app category (messaging)
        • A design study: redesign one notification flow and measure something

        Connected to [[Essay plan: the attention economy]]. If the essay goes well, this could grow out of it.

        Ask Prof. Hart: is a design-led thesis ok in this department?
        """, to: thesis, notesByTitle: byTitle, in: context)

        applyBody("""
        One question per episode. 20 minutes. No intro music, no "welcome back".

        First five questions
        1. Why do we keep buying notebooks we never fill?
        2. Is it possible to be friends with someone you only text?
        3. What did our parents do with their evenings?
        4. Why is every kitchen in a shared flat the same?
        5. Does anyone actually like Sundays?

        Record the first one on Ana's phone, see if we still like the idea after.
        """, to: podcast, notesByTitle: byTitle, in: context)

        applyBody("""
        Things that got easier: the tram, the bakery lady knows my order, I stopped translating prices in my head.

        Things that did not: Sundays. Calling home helps. Cooking helps more.

        What I want to remember from this month: the evening on the roof with Maya and Tom when it rained and nobody wanted to go inside.

        [photo: rooftop.jpg]
        """, to: city, notesByTitle: byTitle, in: context)

        applyBody("""
        Keeping this so next time I do not start from zero.

        • Register address at the city office (took 3 weeks, book early)
        • Student travel card (needs a photo, they are strict about it)
        • Bank: the app works without a local number, the branch does not
        • Find a doctor before you need one
        • Buy a lamp. A real one. The first week in the dark was not fun.

        Still not done
        • Gym
        • A plant that survives me
        """, to: moving, notesByTitle: byTitle, in: context)

        applyBody("""
        As dictated on the phone, so approximate.

        • Rice, the long one, washed until the water is clear
        • Carrots cut into sticks, not grated, she was very firm about this
        • Onions, more than seems reasonable
        • Lamb or chicken, whatever you have
        • Cumin, a lot. Garlic, whole head, pushed into the rice at the end.

        Fry the meat, then onions, then carrots. Water to cover, salt, let it go for 20 minutes. Rice on top, do not stir. Lid on. Wait. Do not stir.

        [photo: plov.jpg]

        She said "you will know when it is ready". I did not know. It was still good.
        """, to: plov, notesByTitle: byTitle, in: context)

        applyBody("""
        Keep it to one page. Three projects, one paragraph each, no "about me" essay.

        Projects to show
        1. The seminar poster (the one Prof. Hart liked)
        2. Café menu redesign for work
        3. Maybe the thesis, once it exists

        Look at how other students do it before building anything. Do not spend the weekend on fonts.
        """, to: portfolio, notesByTitle: byTitle, in: context)
    }

    // MARK: - Побудова rich-тіла нотатки

    /// Міні-розмітка специфікації → наша схема атрибутів:
    /// «> …» — цитата (.embarQuote), «• …» — пункт списку (маркер-гліф
    /// «•⇥» + .embarList, як робить NoteListEngine), «[[Назва]]» — чіп
    /// згадки (.embarMention → реальний backlink через syncMentions),
    /// «[photo: імʼя]» — ряд фото, якщо файл знайдено. Решта — звичайні
    /// абзаци. Косметику (шрифти/кольори/відступи) виводить
    /// NoteFormatter.restyleAllParagraphs з маркерів — тим самим шляхом,
    /// що й вставка
    private static func applyBody(_ raw: String, to note: Note,
                                  notesByTitle: [String: Note],
                                  in context: ModelContext) {
        var raw = raw
        // Фото немає — плейсхолдер зникає разом із порожнім рядком поруч
        for name in ["rooftop.jpg", "plov.jpg"] where demoPhotoURL(name) == nil {
            raw = raw.replacingOccurrences(of: "\n\n[photo: \(name)]", with: "")
            raw = raw.replacingOccurrences(of: "[photo: \(name)]\n\n", with: "")
            raw = raw.replacingOccurrences(of: "[photo: \(name)]", with: "")
        }

        let settings = NoteDocSettings(note: note)
        let doc = NSMutableAttributedString()
        var mentionIDs: Set<UUID> = []
        let lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [
                .embarRole: ParagraphRole.p.rawValue as NSString,
            ]
            var text = line
            if line.hasPrefix("> ") {
                attrs[.embarQuote] = NSNumber(value: true)
                text = String(line.dropFirst(2))
            } else if line.hasPrefix("• ") {
                attrs[.embarList] = ListStyle.bullet.rawValue as NSString
                text = String(line.dropFirst(2))
                doc.append(NSAttributedString(
                    string: NoteFormatter.markerText(.bullet, index: 1),
                    attributes: attrs))
            } else if line.hasPrefix("[photo: "), line.hasSuffix("]") {
                let name = String(line.dropFirst("[photo: ".count).dropLast())
                if let url = demoPhotoURL(name) {
                    let ids = NoteImageStore.importImages(from: [url],
                                                          note: note, in: context)
                    if !ids.isEmpty {
                        let att = EmbarPhotoRowAttachment(
                            imageIDs: ids.map(\.uuidString), columns: 1)
                        doc.append(NSAttributedString(
                            string: "\u{FFFC}",
                            attributes: [
                                .attachment: att,
                                .paragraphStyle: NoteTypography.photoRowParagraphStyle(),
                            ]))
                        if i < lines.count - 1 {
                            doc.append(NSAttributedString(string: "\n",
                                                          attributes: attrs))
                        }
                    }
                }
                continue
            }
            appendInline(text, base: attrs, notesByTitle: notesByTitle,
                         mentions: &mentionIDs, into: doc)
            if i < lines.count - 1 {
                doc.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        NoteFormatter.restyleAllParagraphs(doc, settings: settings)

        if let encoded = NoteArchiver.encode(doc) {
            note.contentData = encoded
            note.contentVersion = 1
        }
        note.content = NoteArchiver.plainText(doc)
        NoteService.syncMentions(mentionIDs, for: note, in: context)
    }

    /// Рядок з інлайн-чіпами: «до [[Назва]] після» → текст + ран чіпа
    /// (титул — той самий chipTitle, що при відкритті звіряє редактор,
    /// інакше він переписував би чіп при кожному відкритті)
    private static func appendInline(_ text: String,
                                     base: [NSAttributedString.Key: Any],
                                     notesByTitle: [String: Note],
                                     mentions: inout Set<UUID>,
                                     into doc: NSMutableAttributedString) {
        var rest = Substring(text)
        while let open = rest.range(of: "[["),
              let close = rest.range(of: "]]",
                                     range: open.upperBound..<rest.endIndex) {
            doc.append(NSAttributedString(string: String(rest[..<open.lowerBound]),
                                          attributes: base))
            let title = String(rest[open.upperBound..<close.lowerBound])
            if let target = notesByTitle[title] {
                var chip = base
                chip[.embarMention] = target.id.uuidString as NSString
                doc.append(NSAttributedString(
                    string: NoteEditorModel.chipTitle(for: target),
                    attributes: chip))
                mentions.insert(target.id)
            } else {
                doc.append(NSAttributedString(string: "[[\(title)]]",
                                              attributes: base))
            }
            rest = rest[close.upperBound...]
        }
        doc.append(NSAttributedString(string: String(rest), attributes: base))
    }

    // MARK: - Рідер

    private static func seedReader(in context: ModelContext) {
        // --- Блокнот 1: Meditations, Marcus Aurelius ---
        let meditations = book("Meditations, Marcus Aurelius",
                               coverIndex: 0, cover: "cover-meditations.jpg",
                               created: daysAgo(15, 20, 0), in: context)
        source("https://www.gutenberg.org/ebooks/2680",
               for: meditations, in: context)

        entry(.thought,
              "Reading this on the tram, ten minutes a day. It is strange how much of it is about mornings.",
              book: meditations, created: daysAgo(14, 8, 20), in: context)
        entry(.quote,
              "When you arise in the morning, think of what a precious privilege it is to be alive, to breathe, to think, to enjoy, to love.",
              author: "Marcus Aurelius",
              book: meditations, created: daysAgo(12, 8, 35),
              highlight: "what a precious privilege", in: context)
        entry(.thought,
              "He wrote this for himself, not for anyone else. That changes how I read it. It is a notebook, not a book.",
              book: meditations, created: daysAgo(10, 22, 10), in: context)

        let book2 = theme("Book 2", in: meditations,
                          created: daysAgo(8, 8, 0), in: context)
        entry(.quote,
              "You have power over your mind, not outside events. Realize this, and you will find strength.",
              author: "Marcus Aurelius",
              book: meditations, theme: book2,
              created: daysAgo(8, 8, 10), favorite: true, in: context)
        entry(.thought,
              "This is the line everyone quotes. Reading it in context it is less of a slogan and more of a reminder he needed every day.",
              book: meditations, theme: book2,
              created: daysAgo(8, 8, 25), in: context)

        entry(.thought,
              "Connects to the essay. He is describing attention without the word.",
              book: meditations, created: daysAgo(5, 21, 30), in: context)
        entry(.quote,
              "The happiness of your life depends upon the quality of your thoughts.",
              author: "Marcus Aurelius",
              book: meditations, created: daysAgo(1, 21, 0), in: context)
        meditations.updatedAt = daysAgo(1, 21, 0)

        // --- Блокнот 2: Cognitive Psychology, lectures ---
        let lectures = book("Cognitive Psychology, lectures",
                            coverIndex: 1, cover: "cover-lectures.jpg",
                            created: daysAgo(13, 10, 0), in: context)

        let week5 = theme("Week 5: Memory", in: lectures,
                          created: daysAgo(12, 10, 0), in: context)
        entry(.thought,
              "Working memory holds about four things, not seven. The seven was a rounding.",
              book: lectures, theme: week5,
              created: daysAgo(12, 10, 15), in: context)
        entry(.thought,
              "Chunking is why phone numbers are written in groups. Also why I remember songs and not dates.",
              book: lectures, theme: week5,
              created: daysAgo(12, 10, 40), in: context)

        let week6 = theme("Week 6: Attention", in: lectures,
                          created: daysAgo(6, 10, 0), in: context)
        entry(.thought,
              "Attention is not a spotlight, it is more like a budget. You do not point it, you spend it.",
              book: lectures, theme: week6,
              created: daysAgo(6, 10, 10), in: context)
        entry(.thought,
              "Every notification is a small withdrawal from that budget, and the interface decides how often to ask.",
              book: lectures, theme: week6,
              created: daysAgo(6, 10, 25),
              highlight: "a small withdrawal from that budget", in: context)
        entry(.question,
              "Does knowing this change anything, or do we just feel worse about scrolling?",
              book: lectures, theme: week6,
              created: daysAgo(5, 13, 5), in: context)
        entry(.thought,
              "Ask Prof. Hart whether the \"budget\" metaphor is in the literature or whether I made it up.",
              book: lectures, theme: week6,
              created: daysAgo(5, 13, 20), in: context)

        entry(.thought,
              "Exam is in December. Start the summary sheet now, not the night before, like last time.",
              book: lectures, created: daysAgo(3, 17, 45), in: context)
        lectures.updatedAt = daysAgo(3, 17, 45)

        // --- Блокнот 3: Podcasts and talks (без обкладинки) ---
        let podcasts = book("Podcasts and talks", coverIndex: 2, cover: nil,
                            created: daysAgo(11, 19, 0), in: context)
        entry(.thought,
              "A designer talking about \"calm technology\". The idea that the best tools stay out of the way until needed.",
              book: podcasts, created: daysAgo(9, 18, 40), in: context)
        entry(.insight,
              "The tools I actually keep using are the ones I do not think about. Everything else gets deleted in a month.",
              book: podcasts, created: daysAgo(7, 22, 20), in: context)
        entry(.thought,
              "Episode about shared flats and why nobody buys a good knife. Sending to Ana, this is episode four.",
              book: podcasts, created: daysAgo(4, 19, 15), in: context)
        // Авторство спірне — цитата свідомо без автора (специфікація)
        entry(.quote,
              "You do not rise to the level of your goals, you fall to the level of your systems.",
              book: podcasts, created: daysAgo(3, 8, 45), in: context)
        entry(.thought,
              "Note to self, stop listening at 1.5x. I remember nothing.",
              book: podcasts, created: daysAgo(1, 8, 30), in: context)
        podcasts.updatedAt = daysAgo(1, 8, 30)
    }

    private static func book(_ title: String, coverIndex: Int, cover: String?,
                             created: Date, in context: ModelContext) -> ReaderBook {
        let b = ReaderBook(title: title)
        b.coverColorIndex = coverIndex
        b.createdAt = created
        b.updatedAt = created
        if let cover, let url = demoPhotoURL(cover),
           let image = NSImage(contentsOf: url),
           let data = NoteImageStore.downscaledJPEG(image) {
            b.photoData = data
        }
        context.insert(b)
        return b
    }

    private static func source(_ raw: String, for book: ReaderBook,
                               in context: ModelContext) {
        let s = ReaderSource(url: ReaderService.normalizedURL(raw),
                             label: ReaderService.sourceLabel(raw))
        s.createdAt = book.createdAt
        s.updatedAt = s.createdAt
        s.book = book
        context.insert(s)
    }

    /// Завершена тема (не активна: нові записи демо-людини йдуть у
    /// загальний потік)
    private static func theme(_ name: String, in book: ReaderBook,
                              created: Date, in context: ModelContext) -> ReaderTheme {
        let t = ReaderTheme(name: name)
        t.isActive = false
        t.createdAt = created
        t.updatedAt = created
        t.book = book
        context.insert(t)
        return t
    }

    @discardableResult
    private static func entry(_ kind: ReaderEntryKind, _ text: String,
                              author: String? = nil,
                              book: ReaderBook, theme: ReaderTheme? = nil,
                              created: Date, favorite: Bool = false,
                              highlight: String? = nil,
                              in context: ModelContext) -> ReaderEntry {
        let e = ReaderEntry(kind: kind, text: text)
        e.author = author
        e.book = book
        e.theme = theme
        e.createdAt = created
        e.updatedAt = created
        e.favorite = favorite
        context.insert(e)
        if let highlight {
            let range = (text as NSString).range(of: highlight)
            if range.location != NSNotFound {
                let h = Highlight(start: range.location,
                                  end: range.location + range.length,
                                  colorName: "yellow", mode: "highlight")
                h.createdAt = created
                h.updatedAt = created
                h.entry = e
                context.insert(h)
            }
        }
        return e
    }

    // MARK: - Фото

    /// Файл за іменем зі специфікації: спершу бандл (Embar/Debug/DemoPhotos/
    /// потрапляє в Resources пласко), потім тека DemoPhotos у контейнері
    /// пісочниці. nil — запис сіється без фото
    private static func demoPhotoURL(_ name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext) {
            return url
        }
        let local = SandboxEnvironment.directoryURL
            .appendingPathComponent("DemoPhotos", isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}
#endif
