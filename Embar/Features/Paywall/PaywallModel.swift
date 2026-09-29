//
//  PaywallModel.swift
//  Embar
//
//  Стан вікна Embar Pro (SPEC §15.77д).
//
//  Ціни живуть у RevenueCat: offerings.current, ідентифікатор offering-а
//  НЕ хардкодиться - пакети шукаємо за типом (.lifetime/.monthly) з
//  фолбеком на product id. Покупка і restore ідуть через
//  EntitlementStore.apply - єдину точку мутації стану доступу.
//
//  Збої не блокують нічого: офлайн чи порожній offering - дружній стан
//  зі «Спробувати ще раз»; сам застосунок працює як працював.
//
//  У пісочниці RC не конфігурований (Purchases.isConfigured == false) -
//  пейвол чесно показує офлайн-стан; покупки тестуються у звичайному
//  Debug зі StoreKit-sandbox акаунтом.
//

import Combine
import Foundation
import RevenueCat
import SwiftData

@MainActor
final class PaywallModel: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md

    enum Phase: Equatable {
        case loading
        case ready
        case purchasing
        case success
        case offline
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var monthly: Package?
    @Published private(set) var lifetime: Package?

    /// Стан ЦІН окремо від фази вікна: .loading / .ready / .offline.
    /// Restore дозволений і поки ціни ще їдуть (рецензія 2026-09-17,
    /// правка 5), тож `load()` і `restore()` можуть накладатись - після
    /// очікування фаза повертається сюди, а не в знімок «що було до»
    private var pricesState: Phase = .loading

    /// Тости цього вікна («Покупок для цього Apple ID не знайдено»):
    /// тост панелі тут не годиться - панель на час restore схована
    let toasts = ToastCenter()

    /// Обраний план (редизайн 2026-09-17): картки перемикаються, купує
    /// один CTA. Типово - lifetime (хендоф)
    enum Plan { case monthly, lifetime }
    @Published var selected: Plan = .lifetime

    var selectedPackage: Package? {
        selected == .lifetime ? (lifetime ?? monthly) : (monthly ?? lifetime)
    }

    /// Думки, що зʼявились після старту trial: стіки (разом із
    /// виконаними й архівними, без видалених) + нотатки + записи й
    /// блокноти Рідера. Рахується ОДИН раз при відкритті пейвола
    let thoughtCount: Int

    /// Стан доступу - ЖИВИЙ, не знімок: зсув дати з пульта чи відповідь
    /// RC мають оновити відкритий пейвол одразу, без перезапуску
    /// (фідбек 2026-09-17). Дзеркало EntitlementStore.shared.access
    @Published private(set) var access: EntitlementStore.Access

    /// Відкрив пейвол, УЖЕ маючи Pro: екран успіху тоді не вітає з
    /// покупкою, а просто дякує за підтримку. Це ЗНІМОК на момент
    /// відкриття - тому окремо від живого access
    let wasProOnOpen: Bool

    private var accessMirror: AnyCancellable?

    /// `context` інʼєктується заради тестів: sharedModelContainer під
    /// XCTest - це РЕАЛЬНА база користувача
    init(context: ModelContext? = nil) {
        let store = EntitlementStore.shared
        // Опціонал, не default-значення: mainContext ізольований на
        // MainActor, а default-параметри обчислюються поза ним
        let context = context ?? EmbarApp.sharedModelContainer.mainContext
        access = store.access
        wasProOnOpen = store.access == .pro
        thoughtCount = Self.countThoughts(since: store.trialStart, in: context)
        if access == .pro { phase = .success }
        accessMirror = store.$access
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.access = $0 }
    }

    // MARK: - Лічильник думок

    static func countThoughts(since start: Date?, in context: ModelContext) -> Int {
        let since = start ?? .distantPast
        func total<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
            (try? context.fetchCount(descriptor)) ?? 0
        }
        return total(FetchDescriptor<Sticker>(predicate: #Predicate {
            $0.deletedAt == nil && $0.createdAt > since }))
            + total(FetchDescriptor<Note>(predicate: #Predicate {
                $0.deletedAt == nil && $0.createdAt > since }))
            + total(FetchDescriptor<ReaderEntry>(predicate: #Predicate {
                $0.deletedAt == nil && $0.createdAt > since }))
            + total(FetchDescriptor<ReaderBook>(predicate: #Predicate {
                $0.deletedAt == nil && $0.createdAt > since }))
    }

    // MARK: - Окупність lifetime
    //
    // «Окупається за N місяців» рахується з РЕАЛЬНИХ цін обох пакетів,
    // а не з константи: інакше зміна ціни в App Store Connect лишила б
    // на пейволі стару цифру (блокер 2026-09-17). Немає котроїсь ціни
    // або місячна нульова - рядок просто не показуємо

    var monthsToPayOff: Int? {
        guard let lifetimePrice = lifetime?.storeProduct.price,
              let monthlyPrice = monthly?.storeProduct.price,
              monthlyPrice > 0 else { return nil }
        let months = (lifetimePrice / monthlyPrice) as NSDecimalNumber
        let rounded = Int(ceil(months.doubleValue))
        return rounded > 1 ? rounded : nil
    }

    // MARK: - Ціни

    func load() async {
        guard phase != .success else { return }
        setPrices(.loading)
        guard Purchases.isConfigured else {
            setPrices(.offline)
            return
        }
        do {
            guard let current = try await Purchases.shared.offerings().current else {
                setPrices(.offline)
                return
            }
            let packages = current.availablePackages
            lifetime = packages.first { $0.packageType == .lifetime }
                ?? packages.first {
                    $0.storeProduct.productIdentifier == ProProducts.lifetime }
            monthly = packages.first { $0.packageType == .monthly }
                ?? packages.first {
                    $0.storeProduct.productIdentifier == ProProducts.monthly }
            // В офферингу лише один план - він і обраний, інакше CTA та
            // юридичний рядок описували б план, якого там немає
            if lifetime == nil, monthly != nil { selected = .monthly }
            if monthly == nil, lifetime != nil { selected = .lifetime }
            setPrices((lifetime == nil && monthly == nil) ? .offline : .ready)
        } catch {
            setPrices(.offline)
        }
    }

    /// Ціни доїхали (чи ні): фаза вікна слідує за ними, ЯКЩО зараз не
    /// йде покупка/restore - тоді очікування само повернеться до
    /// актуального стану цін, коли закінчиться
    private func setPrices(_ state: Phase) {
        pricesState = state
        if phase != .purchasing, phase != .success { phase = state }
    }

    // MARK: - Покупка / відновлення

    /// Очікування затягнулось: показуємо вихід замість вічного чекання
    @Published private(set) var waitIsSlow = false
    /// Скільки чекаємо, перш ніж запропонувати спробувати ще раз
    static let slowWaitSeconds: Double = 30

    /// Лічильник спроб ЦІЄЇ моделі: відповідь СТАРОЇ спроби більше не
    /// чіпає фазу (людина могла натиснути «Спробувати ще раз»), але
    /// entitlement застосовуємо завжди - покупка, що таки пройшла, не
    /// має загубитись. Рівень вікна й панель - НЕ звідси: їх повертає
    /// талон контролера (SystemDialogLedger), спільний для всіх моделей
    private var attempt = 0
    private var slowTimer: Task<Void, Never>?

    func purchase(_ package: Package) async {
        guard phase == .ready else { return }
        // Без configure Purchases.shared - fatalError. У пісочниці RC не
        // конфігурується взагалі - чесний офлайн-стан, не краш
        guard Purchases.isConfigured else { setPrices(.offline); return }
        let token = beginWaiting()
        // Системні вікна StoreKit - поверх пейвола на весь час покупки
        let dialog = PaywallWindowController.shared.beginSystemDialog()
        defer {
            // Рівень і панель повертає лише найновіший талон - контролер
            // сам знає, чи ця спроба ще актуальна
            PaywallWindowController.shared.endSystemDialog(token: dialog)
            endWaiting(token)
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            EntitlementStore.shared.apply(customerInfo: result.customerInfo)
            guard token == attempt else { return }
            phase = EntitlementStore.shared.access == .pro ? .success : pricesState
        } catch {
            // Скасування чи збій - просто повертаємо картки; доступ
            // ніколи не страждає від невдалої покупки
            guard token == attempt else { return }
            phase = pricesState
        }
    }

    /// Відновлення доступне у будь-якому стані цін, навіть поки вони
    /// ще їдуть (правка 5): людина, що вже платила, не мусить чекати
    /// офферинг, щоб повернути своє
    func restore() async {
        guard phase == .ready || phase == .offline || phase == .loading else { return }
        // Краш у пісочниці (2026-09-17): restore ішов у Purchases.shared
        // без configure. Офлайн-стан замість fatalError
        guard Purchases.isConfigured else { setPrices(.offline); return }
        let token = beginWaiting()
        let dialog = PaywallWindowController.shared.beginSystemDialog()
        defer {
            PaywallWindowController.shared.endSystemDialog(token: dialog)
            endWaiting(token)
        }
        do {
            let info = try await Purchases.shared.restorePurchases()
            EntitlementStore.shared.apply(customerInfo: info)
            guard token == attempt else { return }
            if EntitlementStore.shared.access == .pro {
                phase = .success
            } else {
                // Apple відповів, але покупок за цим Apple ID немає -
                // сказати це, а не мовчки повернути картки (правка 5)
                phase = pricesState
                toasts.showMini(Self.nothingToRestoreText)
            }
        } catch {
            guard token == attempt else { return }
            phase = pricesState
        }
    }

    /// Ключ каталогу: uk «Покупок для цього Apple ID не знайдено»,
    /// en "No purchases found for this Apple ID"
    static let nothingToRestoreText = LocalizedStringResource(
        "Покупок для цього Apple ID не знайдено",
        comment: "Тост у пейволі: Restore відповів, але purchases немає")

    /// Людина натиснула «Спробувати ще раз» на довгому очікуванні:
    /// відпускаємо UI назад до карток. Стара спроба, коли відповість,
    /// фазу вже не чіпатиме, але entitlement застосує.
    ///
    /// Рівень вікна й панель НЕ чіпаємо (правка 4): діалог Apple ID,
    /// через який усе й затягнулось, може досі висіти, і піднятий
    /// пейвол знову накрив би його. Їх поверне сам виклик StoreKit,
    /// коли відповість або вийде його власний таймаут (defer у
    /// purchase/restore), або наступна спроба, або закриття вікна
    func giveUpWaiting() {
        guard phase == .purchasing else { return }
        attempt += 1
        slowTimer?.cancel()
        waitIsSlow = false
        phase = pricesState
    }

    private func beginWaiting() -> Int {
        attempt += 1
        let token = attempt
        phase = .purchasing
        waitIsSlow = false
        slowTimer?.cancel()
        slowTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.slowWaitSeconds))
            guard !Task.isCancelled, let self, token == self.attempt,
                  self.phase == .purchasing else { return }
            self.waitIsSlow = true
        }
        return token
    }

    private func endWaiting(_ token: Int) {
        guard token == attempt else { return }
        slowTimer?.cancel()
        waitIsSlow = false
    }
}
