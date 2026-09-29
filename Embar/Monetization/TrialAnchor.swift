//
//  TrialAnchor.swift
//  Embar
//
//  Якір пробного періоду: дата ПЕРШОГО запуску, від якої рахуються
//  14 днів повного доступу (SPEC §15.77в).
//
//  Два рівні зберігання, бо в кожного своя слабкість:
//
//  1. KEYCHAIN (головний). Переживає видалення застосунку і контейнера —
//     перевстановлення не обнуляє trial. Слабкість: рідко, але буває
//     недоступний (збій демона, чужий підпис збірки).
//  2. EmbarDefaults (резерв). Живе в контейнері — видалення контейнера
//     його стирає. Зате завжди доступний.
//
//  Порядок читання: Keychain → defaults → nil. Знайдене лише в одному
//  місці доливається в друге (self-heal). Обидва порожні і запис нікуди
//  не вдався → nil → доступ відкритий: збій зберігання ніколи не
//  замикає людину від її нотаток. А завдяки резерву разовий збій
//  Keychain не робить застосунок безкоштовним назавжди.
//
//  Наявні користувачі бети: дати ніде немає → пишеться «зараз», їхні
//  14 днів починаються з першого запуску цього білда, не заднім числом.
//
//  Ізоляція: та сама триходівка, що в EmbarDefaults.store. Пісочниця і
//  юніт-тести мають ВЛАСНІ Keychain-акаунти (bundle id один на всіх,
//  тож без цього пісочниця тихо мутувала б реальний trial); резерв
//  ізолюється сам — EmbarDefaults.store уже дивиться в потрібний суїт.
//  SandboxEnvironment.wipe() прибирає sandbox-акаунт разом із суїтом.
//

import Foundation
import Security

// MARK: - Спинка Keychain (інʼєкція збоїв у тестах)

/// Мінімальний інтерфейс до Keychain: справжня реалізація ходить у
/// SecItem*, тестова — повертає задані статуси. Юніт-тести НІКОЛИ не
/// торкаються справжнього Keychain (він у хост-застосунку спільний з
/// реальним профілем).
protocol KeychainBacking {
    /// errSecSuccess + дані, errSecItemNotFound, або інший збій
    func read(service: String, account: String) -> (data: Data?, status: OSStatus)
    func write(_ data: Data, service: String, account: String) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

/// Справжній Keychain: data-protection (`kSecUseDataProtectionKeychain`,
/// без ACL-діалогів file-based keychain при зміні підпису) і
/// `ThisDeviceOnly` — trial per-device, в iCloud Keychain не синкається.
struct DataProtectionKeychain: KeychainBacking {
    private func baseQuery(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    func read(service: String, account: String) -> (data: Data?, status: OSStatus) {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (result as? Data, status)
    }

    func write(_ data: Data, service: String, account: String) -> OSStatus {
        var add = baseQuery(service: service, account: account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        return SecItemUpdate(baseQuery(service: service, account: account) as CFDictionary,
                             [kSecValueData as String: data] as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}

// MARK: - Якір

enum TrialAnchor {
    static let service = "nechai.Embar.trial"

    /// Ключ резерву в EmbarDefaults (суїт сам ізолює пісочницю/тести)
    static let fallbackKey = "trialStartFallback"

    /// Той самий детектор середовища, що в EmbarDefaults.store:
    /// юніт-тести → свій акаунт, пісочниця → свій, інакше — справжній
    static var account: String {
        if NSClassFromString("XCTestCase") != nil { return "UnitTests.trialStart" }
        if SandboxEnvironment.isActive { return "TestSandbox.trialStart" }
        return "trialStart"
    }

    // MARK: Читання/встановлення

    /// Дата старту trial. Немає ніде → записує `now` в обидва рівні
    /// (перший запуск або міграція бети). Повертає nil ЛИШЕ якщо дати
    /// немає і жоден запис не вдався — виклик трактує це як відкритий
    /// доступ.
    static func readOrEstablish(now: Date = .now,
                                backing: KeychainBacking = DataProtectionKeychain(),
                                defaults: UserDefaults = EmbarDefaults.store) -> Date? {
        let keychainDate = readKeychainDate(backing: backing)
        let fallbackDate = (defaults.object(forKey: fallbackKey) as? Double)
            .map { Date(timeIntervalSinceReferenceDate: $0) }

        switch (keychainDate, fallbackDate) {
        case let (.some(date), .none):
            // Резерв загубився (наприклад, wipe контейнера) — долити
            defaults.set(date.timeIntervalSinceReferenceDate, forKey: fallbackKey)
            return date
        case let (.some(date), .some):
            return date
        case let (.none, .some(date)):
            // Keychain мовчить, резерв живий: спробувати вилікувати і
            // працювати далі від резервної дати
            _ = writeKeychainDate(date, backing: backing)
            return date
        case (.none, .none):
            let keychainOK = writeKeychainDate(now, backing: backing)
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: fallbackKey)
            let fallbackOK =
                (defaults.object(forKey: fallbackKey) as? Double) != nil
            return (keychainOK || fallbackOK) ? now : nil
        }
    }

    private static func readKeychainDate(backing: KeychainBacking) -> Date? {
        let (data, status) = backing.read(service: service, account: account)
        guard status == errSecSuccess, let data,
              let text = String(data: data, encoding: .utf8),
              let interval = Double(text) else { return nil }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    private static func writeKeychainDate(_ date: Date,
                                          backing: KeychainBacking) -> Bool {
        let data = Data(String(date.timeIntervalSinceReferenceDate).utf8)
        return backing.write(data, service: service, account: account) == errSecSuccess
    }

    // MARK: - Дебаг (лише пісочниця)

    #if DEBUG
    /// «Перевести дату вперед»: зсунути ЗБЕРЕЖЕНИЙ старт назад — для
    /// логіки це те саме, що прожити N днів, але без глобальної
    /// абстракції часу (якої в проєкті свідомо немає)
    @discardableResult
    static func shift(byDays days: Int,
                      backing: KeychainBacking = DataProtectionKeychain(),
                      defaults: UserDefaults = EmbarDefaults.store) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        guard let current = readOrEstablish(backing: backing,
                                            defaults: defaults) else { return false }
        let shifted = current.addingTimeInterval(-Double(days) * 86_400)
        defaults.set(shifted.timeIntervalSinceReferenceDate, forKey: fallbackKey)
        let keychainOK = writeKeychainDate(shifted, backing: backing)
        // Як у readOrEstablish: зсув «є», якщо його тримає хоч один
        // рівень. Раніше false від Keychain ховав уже записаний резерв,
        // і пульт не перераховував стан (фідбек 2026-09-17)
        let fallbackOK = (defaults.object(forKey: fallbackKey) as? Double)
            == shifted.timeIntervalSinceReferenceDate
        return keychainOK || fallbackOK
    }

    /// Прибрати якір з ОБОХ рівнів (наступне читання почне trial заново)
    @discardableResult
    static func reset(backing: KeychainBacking = DataProtectionKeychain(),
                      defaults: UserDefaults = EmbarDefaults.store) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        defaults.removeObject(forKey: fallbackKey)
        let status = backing.delete(service: service, account: account)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    #endif
}
