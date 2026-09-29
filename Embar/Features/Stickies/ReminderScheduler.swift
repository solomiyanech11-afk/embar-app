//
//  ReminderScheduler.swift
//  Embar
//
//  Локальні сповіщення про дедлайни стіків (SPEC §2.4, Embar.md §12).
//  Дозвіл запитується ЛАЗІ — коли реально є що планувати, не при старті.
//  Жодних додаткових entitlements: UNUserNotificationCenter працює в
//  sandbox для підписаного застосунку.
//
//  Сповіщення приходить у момент «дедлайн мінус зсув» (StickyNotify).
//  Заголовок — текст стіка, тіло — деталі й стіна; дві дії просто з банера:
//  «Готово» і «Відкласти на 10 хв». Клік по банеру веде до самого стіка.
//

import AppKit
import Foundation
import UserNotifications

enum ReminderScheduler {

    // MARK: - Категорія і дії

    static let categoryID = "stickyDeadline"

    enum Action {
        /// Просто прибрати банер, нічого не роблячи зі стіком
        static let close = "close"
        static let done = "done"
        static let snooze = "snooze10"
    }

    /// На скільки відкладає кнопка «Відкласти»
    static let snoozeMinutes = 10

    /// Реєструвати при старті: без категорії банер не покаже кнопок.
    /// Назви дій запікаються тут — тому переклад оновлюється з перезапуском
    /// (як і тексти вже запланованих сповіщень)
    static func registerCategories() {
        let close = UNNotificationAction(
            identifier: Action.close,
            title: String(localized: "Закрити", comment: "Кнопка на сповіщенні про дедлайн стіка"),
            options: [])
        let done = UNNotificationAction(
            identifier: Action.done,
            title: String(localized: "Позначити виконаним", comment: "Кнопка на сповіщенні про дедлайн стіка"),
            options: [])
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: String(localized: "Відкласти на 10 хв", comment: "Кнопка на сповіщенні про дедлайн стіка"),
            options: [])
        let category = UNNotificationCategory(
            identifier: categoryID, actions: [close, done, snooze],
            intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Дозвіл

    /// Лазі-запит дозволу. Повертає true, якщо сповіщення дозволені
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Кешований статус дозволу для СИНХРОННИХ рішень UI (F6,
    /// 2026-08-31): справжній статус лише async, а вирішувати, чи вмикати
    /// нагадування і що обіцяти в тості, треба В МОМЕНТ дії. `nil` —
    /// систему в цьому сеансі ще не питали. Оновлюється при старті, при
    /// поверненні застосунку на передній план (людина ходила в системні
    /// параметри) і кожним async-чеком
    private(set) static var cachedStatus: UNAuthorizationStatus?

    /// Дозвіл ЯВНО відхилено. ❗ true лише для `.denied`: «ще не питали»
    /// (`.notDetermined`) — НЕ відмова, лазі-запит при першому
    /// нагадуванні лишається як був (§12)
    static var cachedDenied: Bool { cachedStatus == .denied }

    /// Система дала остаточну відповідь. Поки false, обіцяти НІЧОГО не
    /// можна: системне віконце ще на екрані, і «Нагадаю о …» стало б
    /// обіцянкою навмання (ревʼю 2026-08-31, пункт 3)
    static var cachedResolved: Bool {
        cachedStatus == .denied || cachedStatus == .authorized
    }

    /// Освіжити кеш у фоні — байдуже коли доїде, аби до наступної дії
    static func refreshStatusCache() {
        Task { _ = await ensureAuthorized(ask: false) }
    }

    /// Дозвіл є? `ask` вмикає лазі-запит — його ставить лише дія людини
    /// (поставила нагадування), ніколи фонове перепланування: системне
    /// віконце просто так, на старті, — це саме те, чого §12 не хоче
    static func ensureAuthorized(ask: Bool) async -> Bool {
        var status = await authorizationStatus()
        var granted = status == .authorized
        if status == .notDetermined, ask {
            granted = await requestAuthorization()
            // Кеш — зі свіжого статусу, не з granted: збій запиту
            // (catch → false) лишає .notDetermined, і це НЕ відмова
            status = await authorizationStatus()
        }
        cachedStatus = status
        return granted
    }

    // MARK: - Планування

    /// Знімок стіка: у планувальник ідуть значення, а не модель SwiftData
    struct Job {
        let id: UUID
        let title: String
        let details: String
        let wallName: String?
        let at: Date
    }

    /// Чи цьому стіку взагалі належать сповіщення — без огляду на час.
    /// Виконаний, заархівований чи видалений стік не нагадує про себе.
    /// Одне правило на всіх: і планування, і кнопка «Відкласти»
    static func canRemind(_ sticker: Sticker) -> Bool {
        sticker.deletedAt == nil && !sticker.archived && !sticker.done
    }

    /// Що саме треба запланувати для цього стіка — або нічого.
    /// Минулий час не планується (сповіщення «навздогін» не буває)
    static func job(for sticker: Sticker) -> Job? {
        guard canRemind(sticker),
              let deadline = sticker.deadline,
              let offset = sticker.notifyOffsetMinutes else { return nil }
        let at = StickyNotify.triggerDate(deadline: deadline, offsetMinutes: offset)
        guard at > .now else { return nil }
        let wall = sticker.wall
        // Текст ріжемо ТУТ, а не при показі: знімок має бути тим самим, що
        // побачить людина, — інакше його не перевірити тестом
        return Job(id: sticker.id,
                   title: clip(sticker.text, limit: titleTextLimit),
                   details: clip(sticker.bodyText, limit: bodyLimit),
                   wallName: (wall?.deletedAt == nil) ? wall?.name : nil, at: at)
    }

    // MARK: - Довжина тексту в банері

    /// Скільки символів лишаємо в заголовку РАЗОМ із префіксом. Далі система
    /// ріже сама — але вже посеред слова і без «…», тож робимо своїми руками
    static let titleLimit = 60
    /// Деталі стіка бувають довгі; тіло банера все одно показує ~2 рядки
    static let bodyLimit = 140

    /// Заголовок банера починається з «Нагадування:» — запікається при
    /// плануванні, як і решта текстів (мова оновлюється з перезапуском)
    static var titlePrefix: String {
        String(localized: "Нагадування:", comment: "Префікс заголовка сповіщення про дедлайн стіка")
    }

    /// Скільки з ліміту лишається самому тексту стіка після префікса
    /// і пробіла за ним
    static var titleTextLimit: Int {
        max(20, titleLimit - titlePrefix.count - 1)
    }

    /// Обрізати текст до ліміту по межі слова. Однорядково: переноси в
    /// заголовку банера все одно схлопуються, тож замінюємо їх пробілом
    static func clip(_ text: String, limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        let head = flat.prefix(limit)
        // Відступаємо назад до пробілу — але не далі, ніж на третину:
        // одне довге слово (посилання) інакше зрізало б майже все
        if let space = head.lastIndex(where: { $0.isWhitespace }),
           head.distance(from: head.startIndex, to: space) >= limit * 2 / 3 {
            return head[..<space].trimmingCharacters(in: .whitespaces) + "…"
        }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// ЄДИНА точка перепланування: спершу знімаємо старе сповіщення, потім
    /// ставимо нове, якщо є за що. Викликати після будь-якої зміни стіка,
    /// що впливає на сповіщення (дедлайн, зсув, done, архів, видалення).
    ///
    /// `askPermission` — це дія людини, а не фон: тільки тоді можна
    /// показати системний запит дозволу і поскаржитись через `onDenied`
    /// `onResolved` — система дала остаточну відповідь на запит дозволу
    /// (true = дозволено). Кличеться ЛИШЕ коли ми справді питали
    /// (`askPermission`) і є що планувати. Через нього UI показує
    /// правдивий тост ПІСЛЯ відповіді, а не обіцянку навмання
    /// (ревʼю 2026-08-31, пункт 3)
    static func replan(for sticker: Sticker, askPermission: Bool = false,
                       onResolved: ((Bool) -> Void)? = nil) {
        // ❗ id беремо ДО async: модель SwiftData прив'язана до свого
        // контексту, і за межі синхронного шматка її тягнути не можна —
        // якщо контекст встигне зникнути, звернення до неї валить процес
        let id = sticker.id
        // Покоління беремо ПРЯМО зі скасування, а не окремим читанням:
        // між двома зверненнями встигало вклинитись чуже перепланування,
        // і застаріле завдання вважало себе свіжим
        let token = cancel(id: id)
        guard let job = job(for: sticker) else { return }
        Task {
            let granted = await ensureAuthorized(ask: askPermission)
            if askPermission { onResolved?(granted) }
            guard granted else { return }
            // Поки це завдання чекало на дозвіл, могло прийти новіше
            // (степер хвилин легко дає кілька за секунду) — застаріле не
            // має перебити свіже (ревʼю 2026-08-19)
            guard generationToken(for: id) == token else { return }
            await schedule(job)
        }
    }

    // MARK: - Лічильник перепланувань

    /// Лічильник перепланувань на стік. Живе лише в памʼяті сеансу.
    ///
    /// ❗ ПІД ЗАМКОМ. `replan` продовжується у `Task` на кооперативному
    /// пулі, а `cancel` кличуть і з головного потоку (степер у стіку), і
    /// з фонових задач (`relocalizeRemindersIfLanguageChanged`). Swift
    /// Dictionary не витримує одночасних читання й запису: кілька швидких
    /// натисків «Нагадати» давали пошкодження памʼяті, а не просто
    /// неправильне число (ревʼю 2026-08-20)
    private static var generation: [UUID: Int] = [:]
    private static let generationLock = NSLock()

    /// Не private: лічильник перевіряється тестом напряму — інакше
    /// втрачені інкременти не побачити
    static func generationToken(for id: UUID) -> Int {
        generationLock.withLock { generation[id] ?? 0 }
    }

    private static func bumpGeneration(for id: UUID) -> Int {
        generationLock.withLock {
            let next = (generation[id] ?? 0) + 1
            generation[id] = next
            return next
        }
    }

    static func schedule(_ job: Job) async {
        guard job.at > .now else { return }
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: job.at)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        await add(content: content(for: job), id: job.id, trigger: trigger)
    }

    /// Кнопка «Відкласти»: той самий зміст ще раз, через 10 хвилин.
    /// Дедлайн стіка НЕ рухається — відкладається лише нагадування.
    /// ❗ Чи стік іще живий, перевіряє той, хто кличе (AppDelegate): сюди
    /// приходить уже доставлений контент, а не модель
    static func snooze(content: UNNotificationContent, id: UUID) async {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(snoozeMinutes) * 60, repeats: false)
        // Копія: доставлений контент назад у запит не віддаси
        let copy = UNMutableNotificationContent()
        copy.title = content.title
        copy.body = content.body
        copy.sound = .default
        copy.categoryIdentifier = categoryID
        copy.userInfo = content.userInfo
        await add(content: copy, id: id, trigger: trigger)
    }

    /// Юніт-тести хостяться в самому Embar, і дозвіл на сповіщення в
    /// нього справжній: без цього запобіжника replan із тестових фікстур
    /// ставив СИСТЕМІ реальні банери («Нагадування: Старий стік» тощо
    /// після кожного прогону тестів — знахідка 2026-08-20)
    private static let isTestRun = NSClassFromString("XCTestCase") != nil

    /// id запиту = id стіка: одне сповіщення на стік, легко скасувати й оновити
    private static func add(content: UNNotificationContent, id: UUID,
                            trigger: UNNotificationTrigger) async {
        guard !isTestRun else { return }
        let request = UNNotificationRequest(
            identifier: id.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Не private: фінальний вміст банера перевіряється тестом напряму —
    /// порожній заголовок одного разу вже шукали всім селом
    static func content(for job: Job) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // job.title/details уже обрізані в job(for:) з урахуванням префікса
        let text = job.title.isEmpty
            ? String(localized: "Стік", comment: "Заголовок сповіщення, коли стік без тексту")
            : job.title
        content.title = titlePrefix + " " + text
        // Тіло: деталі стіка і стіна, на якій він живе
        content.body = [job.details, job.wallName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["stickerID": job.id.uuidString]
        return content
    }

    // MARK: - Системні параметри

    /// Чи банер зникає за кілька секунд, чи чекає на екрані — вирішує стиль
    /// сповіщень у системних параметрах, і застосунок не може змінити його
    /// за людину. Тож лишається відчинити їй потрібні двері
    static func openSystemNotificationSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Знімає і заплановане, і вже показане: банер не має пережити стік.
    /// Заразом старить завдання, що вже в польоті, — воно нічого не
    /// поставить. Повертає нове покоління (потрібне `replan`)
    @discardableResult
    static func cancel(id: UUID) -> Int {
        let token = bumpGeneration(for: id)
        guard !isTestRun else { return token }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        return token
    }

    // MARK: - Прибирання сиріт

    /// Чисте правило «що зайве» — окремо від системного центру, щоб його
    /// покривав тест: зайвий = наша категорія, але id не з дозволеного
    /// набору (або взагалі не UUID)
    static func staleIdentifiers(among items: [(id: String, category: String)],
                                 keeping valid: Set<UUID>) -> [String] {
        items.filter { item in
            item.category == categoryID &&
            (UUID(uuidString: item.id).map { !valid.contains($0) } ?? true)
        }.map(\.id)
    }

    /// Зняти з системи сповіщення, яких уже не мусить бути: стіка нема в
    /// базі, або він виконаний, заархівований чи видалений. Ловить і
    /// хвости тестових прогонів (тести хостяться в застосунку і колись
    /// планували справжні банери).
    ///
    /// ❗ Правило одне на все — `canRemind`, і воно НЕ дивиться на час.
    /// Раніше список «кому дозволено чекати в черзі» будувався з
    /// `job(for:)`, який вимагає МАЙБУТНЬОГО тригера, — і відкладене
    /// сповіщення не потрапляло туди ніколи: воно за визначенням
    /// належить стіку з уже минулим дедлайном. Обслуговування зносило
    /// його при першому ж запуску, пробудженні зі сну чи опівночі, і
    /// «Відкласти на 10 хв» тихо не приходило (ревʼю 2026-08-20).
    /// Чи є ще ЩО планувати — справа `replan`, а не прибиральника
    static func pruneOrphans(keeping valid: Set<UUID>) async {
        guard !isTestRun else { return }
        let center = UNUserNotificationCenter.current()
        let queued = await center.pendingNotificationRequests()
            .map { (id: $0.identifier, category: $0.content.categoryIdentifier) }
        let stalePending = staleIdentifiers(among: queued, keeping: valid)
        if !stalePending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stalePending)
        }
        let shown = await center.deliveredNotifications()
            .map { (id: $0.request.identifier,
                    category: $0.request.content.categoryIdentifier) }
        let staleShown = staleIdentifiers(among: shown, keeping: valid)
        if !staleShown.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleShown)
        }
    }
}
