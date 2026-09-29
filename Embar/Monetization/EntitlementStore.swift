//
//  EntitlementStore.swift
//  Embar
//
//  Єдине джерело стану доступу (SPEC §15.77): trial / pro / режим
//  читання. Політика стійкості - краще дати зайвий доступ, ніж
//  замкнути людину від її нотаток:
//
//  · старт СИНХРОННИЙ і ЛОКАЛЬНИЙ (Keychain-якір + кеш у defaults),
//    жодного очікування мережі;
//  · RevenueCat відповідає асинхронно через customerInfoStream, кожна
//    відповідь кешується - офлайн застосунок живе з останнім відомим
//    статусом;
//  · trial минув, а RC ще ЖОДНОГО разу не відповідав (кеш відсутній) →
//    доступ відкритий. Режим читання вмикається лише коли кеш явно
//    каже «не pro».
//
//  Мутації стану - тільки тут і тільки на MainActor: bootstrap при
//  старті, apply з відповідей RC, дебаг-перерахунок. Гонок немає за
//  побудовою.
//
//  Пісочниця: RC не конфігурується ВЗАГАЛІ (офлайн, внутрішній кеш RC
//  у standard defaults не забруднюється спільним bundle id); роль кешу
//  грає тристановий SandboxProOverride - без нього режим читання в
//  пісочниці був би недосяжним.
//

import AppKit
import Combine
import Foundation
import RevenueCat

/// Ідентифікатори App Store Connect. Offering свідомо НЕ хардкодиться -
/// беремо offerings.current (SPEC §15.77а)
enum ProProducts {
    static let entitlementID = "pro"
    static let monthly = "nechai.Embar.pro.monthly"
    static let lifetime = "nechai.Embar.pro.lifetime"
    /// Публічний SDK-ключ RevenueCat - не секрет, у коді дозволений
    static let revenueCatAPIKey = "appl_dbfPvGfoZlRLsUedyTqfVRFyvqd"
}

@MainActor
final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()
    nonisolated deinit {}

    /// Стан доступу. `open` - свідомий fail-open: збій зберігання або
    /// «RC ще не відповідав» ніколи не блокують
    enum Access: Equatable {
        case trial(daysLeft: Int)   // 1...14
        case pro
        case readOnly               // trial минув І кеш каже «не pro»
        case open
    }

    @Published private(set) var access: Access = .open
    /// pro походить з активної місячної підписки (не lifetime) - для
    /// рядка «Керувати підпискою»; кешується, тож працює й офлайн
    @Published private(set) var proIsSubscription = false

    /// Останнє відоме слово RC: ключа немає = не відповідав ніколи
    static let cacheKey = "proEntitlementCache"
    static let cacheSubscriptionKey = "proIsSubscriptionCache"
    #if DEBUG
    /// Тристановий оверайд пісочниці: немає = без оверайду, 1 = pro,
    /// 0 = «кеш каже не pro» (єдиний шлях до readOnly в пісочниці).
    ///
    /// ❗ Значення ключа НЕ дорівнює імені аргументу запуску
    /// (`-SandboxProOverride`): аргументи лягають у argument domain, який
    /// перекриває суїт, і приходять РЯДКОМ - `as? Int` давав nil, тож
    /// оверайд тихо не працював узагалі (знайдено 2026-09-17)
    static let sandboxOverrideKey = "sandboxProOverrideValue"
    #endif

    private(set) var trialStart: Date?

    /// Головне питання гейтів створення
    var canCreate: Bool { access != .readOnly }

    // MARK: - Старт

    /// Синхронно, без мережі: прочитати/встановити якір і порахувати
    /// стан з локального кешу. Викликається один раз при старті
    func bootstrap(now: Date = .now,
                   backing: KeychainBacking = DataProtectionKeychain()) {
        trialStart = TrialAnchor.readOrEstablish(now: now, backing: backing)
        recompute(now: now)
    }

    /// Перерахувати стан із того, що вже лежить локально. Дебаг-команди
    /// пісочниці кличуть це після мутацій якоря/оверайду, годинник
    /// (`startClock`) - на кожному тику часу
    func recompute(now: Date = .now) {
        let cached = Self.effectiveCachedPro(defaults: EmbarDefaults.store)
        access = Self.computeAccess(trialStart: trialStart,
                                    cachedPro: cached, now: now)
        proIsSubscription = access == .pro
            && EmbarDefaults.store.bool(forKey: Self.cacheSubscriptionKey)
    }

    // MARK: - Годинник (рецензія 2026-09-17, правка 1)
    //
    // Embar живе в меню тижнями без релаунчу. Стан, порахований лише при
    // старті, означав би, що trial ніколи не минає, а «Лишилось N дн.»
    // у пігулці пейвола і картці налаштувань застигає. Тому recompute
    // кличеться на кожному природному тику часу: перехід доби,
    // пробудження зі сну, активація застосунку, і таймером раз на
    // годину (на випадок, якщо жодна з подій довго не приходить).
    // Рахунок дешевий - кілька читань defaults, без мережі.

    /// Раз на годину; tolerance дає системі згрупувати пробудження
    static let clockInterval: TimeInterval = 3_600

    private var clockObservers: [NSObjectProtocol] = []
    private var clockTimer: Timer?

    /// Підписатись на тики часу. Ідемпотентно: повторний виклик нічого
    /// не додає
    func startClock() {
        guard clockObservers.isEmpty else { return }
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let sources: [(NotificationCenter, Notification.Name)] = [
            (app, .NSCalendarDayChanged),
            (workspace, NSWorkspace.didWakeNotification),
            (app, NSApplication.didBecomeActiveNotification),
        ]
        // Обидва колбеки приходять на головному потоці (queue: .main і
        // таймер головного runloop) - assumeIsolated чесний і
        // синхронний: тест постить нотифікацію і одразу читає стан
        clockObservers = sources.map { center, name in
            center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.clockInterval,
                                         repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        timer.tolerance = 60
        clockTimer = timer
    }

    /// Для тестів: зняти підписки, щоб інстанси не накопичувались
    func stopClock() {
        clockObservers.forEach { NotificationCenter.default.removeObserver($0) }
        clockObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        clockObservers = []
        clockTimer?.invalidate()
        clockTimer = nil
    }

    // MARK: - Чиста політика (юніт-тести ганяють саме це)

    /// 14 повних днів = рівно 14×86400 с від першого запуску - без
    /// календарних і DST-країв. Відкат годинника trial не подовжує
    /// (clamp до 14)
    nonisolated static func computeAccess(trialStart: Date?,
                                          cachedPro: Bool?,
                                          now: Date) -> Access {
        if cachedPro == true { return .pro }
        // Якоря немає ніде (збій обох рівнів) - не блокуємо
        guard let start = trialStart else { return .open }
        let end = start.addingTimeInterval(14 * 86_400)
        if now < end {
            let daysLeft = Int(ceil(end.timeIntervalSince(now) / 86_400))
            return .trial(daysLeft: min(14, max(1, daysLeft)))
        }
        // Минув: блокуємо лише при явному «не pro» від RC
        return cachedPro == false ? .readOnly : .open
    }

    /// Що вважати «кешем RC»: у пісочниці - тристановий оверайд,
    /// інакше - справжній кеш. Параметр isSandbox існує заради тестів
    nonisolated static func effectiveCachedPro(
        defaults: UserDefaults,
        isSandbox: Bool = SandboxEnvironment.isActive) -> Bool? {
        #if DEBUG
        if isSandbox {
            guard let raw = defaults.object(forKey: sandboxOverrideKey) as? Int
            else { return nil }
            return raw != 0
        }
        #endif
        return defaults.object(forKey: cacheKey) as? Bool
    }

    // MARK: - RevenueCat

    /// Конфігурація SDK і підписка на потік статусів. Не блокує:
    /// configure повертається одразу, відповіді приходять у Task
    func startPurchases() {
        #if DEBUG
        // Пісочниця живе офлайн - стан керується якорем і оверайдом
        if SandboxEnvironment.isActive { return }
        #endif
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: ProProducts.revenueCatAPIKey)
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: info)
            }
        }
    }

    /// Єдина точка входу відповідей RC (стрім, покупка, restore)
    func apply(customerInfo info: CustomerInfo, now: Date = .now) {
        let entitlement = info.entitlements.active[ProProducts.entitlementID]
        applyProStatus(entitlement != nil,
                       isSubscription:
                        entitlement?.productIdentifier == ProProducts.monthly,
                       now: now)
    }

    #if DEBUG
    /// «Скинути стан покупки» (2026-09-17): після Clear Purchase History
    /// в App Store Connect - пройти покупку заново у звичайному Debug.
    /// Чистить лише КЕШ статусу (наш і RevenueCat), даних не чіпає;
    /// свідомо працює і поза пісочницею, бо покупка тестується там,
    /// де RC сконфігурований. У пісочниці RC немає - чистимо своє
    func debugResetPurchaseState() async {
        let d = EmbarDefaults.store
        d.removeObject(forKey: Self.cacheKey)
        d.removeObject(forKey: Self.cacheSubscriptionKey)
        d.removeObject(forKey: Self.sandboxOverrideKey)
        if Purchases.isConfigured {
            Purchases.shared.invalidateCustomerInfoCache()
            // Новий анонімний користувач RC - щоб бекенд не памʼятав
            // старий entitlement. Для вже-анонімного logOut кидає
            // помилку - це очікувано, кеш уже інвалідовано вище
            _ = try? await Purchases.shared.logOut()
        }
        recompute()
    }
    #endif

    /// Відокремлено від CustomerInfo, щоб тести не мокали RC
    func applyProStatus(_ isPro: Bool, isSubscription: Bool, now: Date = .now) {
        let defaults = EmbarDefaults.store
        defaults.set(isPro, forKey: Self.cacheKey)
        defaults.set(isPro && isSubscription, forKey: Self.cacheSubscriptionKey)
        recompute(now: now)
    }
}
