//
//  SandboxEnvironment.swift
//  Embar
//
//  ТЕСТОВЕ СЕРЕДОВИЩЕ (`-EmbarTestSandbox`): застосунок працює на
//  ПОВНІСТЮ окремих даних — власний файл бази SwiftData і власний суїт
//  UserDefaults. Реальні дані при цьому не читаються і не пишуться.
//
//  Дві межі, які тримають ізоляцію:
//
//  1. БАЗА. Звичайний запуск бере дефолтне сховище SwiftData (default.store
//     у Application Support контейнера). Пісочниця — окремий файл у
//     підпапці EmbarTestSandbox/. Різні файли, спільного стану немає.
//
//  2. НАЛАШТУВАННЯ. Увесь застосунок пише не в `UserDefaults.standard`, а
//     в `EmbarDefaults.store`. У звичайному запуску це і є `.standard`;
//     у пісочниці — окремий суїт (окремий .plist у Preferences
//     контейнера). Суїт НЕ читає домен застосунку — перевірено тестом
//     SandboxIsolationTests, — тож прапорці онбордингу, палітра,
//     позиції віджетів у пісочниці стартують чистими.
//
//  Що суїт усе-таки бачить — глобальний домен macOS (мова системи,
//  24-годинний час) і домен аргументів запуску. Це системні речі, не
//  наші дані, і саме така поведінка нам потрібна.
//
//  ⚠️ Наслідок для пісочниці: вибір мови в Settings пише `AppleLanguages`
//  у суїт, а система при старті читає домен ЗАСТОСУНКУ — тож у пісочниці
//  перемикач мови не спрацює. Це свідома ціна ізоляції: писати туди
//  по-справжньому означало б чіпати реальні налаштування. Для перевірки
//  мови є окремі схеми «Embar (UK)» / «Embar (EN)».
//

import Foundation

// MARK: - Аргументи запуску

/// Читання прапорців ПРЯМО з командного рядка, повз UserDefaults.
///
/// Через `UserDefaults` це теж працює (домен аргументів), але саме тут
/// покладатись на нього не можна: пісочниця вирішує, ЯКИЙ об'єкт
/// UserDefaults створювати, — питати про це сам UserDefaults було б
/// колом у визначенні.
enum LaunchArgs {
    /// Значення, записане ПРИ прапорці: `-Name YES` одним рядком або
    /// `-Name=YES`. Xcode у списку «Arguments Passed On Launch» може
    /// віддати рядок і цілим шматком, і розбитим по пробілу — тому
    /// розбираємо обидві форми, інакше галочка в схемі мовчки нічого
    /// не робила б
    private static func inlineValue(_ name: String, in arg: String) -> String? {
        let flag = "-" + name
        if arg == flag { return nil }
        for separator in [" ", "="] where arg.hasPrefix(flag + separator) {
            return String(arg.dropFirst(flag.count + 1))
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Індекс аргумента, що починається з `-Name` (сам прапорець або
    /// прапорець зі значенням в одному рядку)
    private static func index(of name: String, in args: [String]) -> Int? {
        let flag = "-" + name
        return args.firstIndex {
            $0 == flag || $0.hasPrefix(flag + " ") || $0.hasPrefix(flag + "=")
        }
    }

    /// `-Name`, `-Name YES`, `-Name 1` → true; `-Name NO|0|false` → false.
    /// Параметр `args` існує лише заради тестів розбору
    static func flag(_ name: String,
                     in args: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard let i = index(of: name, in: args) else { return false }
        let value = (inlineValue(name, in: args[i])
                     ?? (args.indices.contains(i + 1) ? args[i + 1] : ""))
            .lowercased()
        // Наступний аргумент — уже інший прапорець: голий -Name = увімкнено
        if value.isEmpty || value.hasPrefix("-") { return true }
        return !["no", "0", "false"].contains(value)
    }

    /// Число після прапорця: `-Name 5000` (двома аргументами чи одним)
    static func int(_ name: String,
                    in args: [String] = ProcessInfo.processInfo.arguments) -> Int? {
        guard let i = index(of: name, in: args) else { return nil }
        if let inline = inlineValue(name, in: args[i]) { return Int(inline) }
        guard args.indices.contains(i + 1) else { return nil }
        return Int(args[i + 1])
    }
}

// MARK: - Пісочниця

enum SandboxEnvironment {
    /// Прапорець схеми «Embar (Sandbox)»
    static let flagName = "EmbarTestSandbox"

    /// Рахуємо ОДИН раз за процес: режим не може змінитись на льоту,
    /// а половина застосунку в пісочниці, половина в реальних даних —
    /// найгірше, що могло б статись.
    ///
    /// У Release-збірці пісочниці не існує: доведено аудитом перед
    /// TestFlight (2026-09-05), що `-EmbarTestSandbox` умикав тестовий
    /// режим і в релізному бінарнику. Даним це не загрожувало, але
    /// тест-режим не має їхати до користувачів
    static let isActive: Bool = {
        #if DEBUG
        return LaunchArgs.flag(flagName)
        #else
        return false
        #endif
    }()

    /// Окремий .plist у Preferences контейнера. Назва свідомо НЕ дорівнює
    /// bundle id — інакше це був би той самий домен, що й реальний
    static let defaultsSuiteName = "nechai.Embar.TestSandbox"

    /// Підпапка, у якій живе геть усе тестове. Тільки її прибирає wipe()
    static let folderName = "EmbarTestSandbox"

    /// Application Support/EmbarTestSandbox (усередині контейнера —
    /// App Sandbox увімкнено, тож це не «системна» тека)
    static var directoryURL: URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Файл бази SwiftData пісочниці
    static var storeURL: URL {
        directoryURL.appendingPathComponent("sandbox.store")
    }

    /// Створити теку під базу (SwiftData сам її не створює)
    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Очищення

    /// Прибрати геть усе тестове: файл бази (з -wal/-shm) і суїт налаштувань.
    ///
    /// Два запобіжники, бо ціна помилки — реальні дані користувача:
    /// · працює ЛИШЕ коли процес запущено з прапорцем пісочниці;
    /// · видаляє лише теку, що зветься рівно folderName.
    /// Повертає false, якщо не спрацювало (нічого не видалено).
    @discardableResult
    static func wipe() throws -> Bool {
        guard isActive else { return false }
        let dir = directoryURL
        guard dir.lastPathComponent == folderName else { return false }
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        EmbarDefaults.store.removePersistentDomain(forName: defaultsSuiteName)
        #if DEBUG
        // Trial-якір пісочниці живе НЕ в теці і НЕ в суїті, а в Keychain
        // (окремий акаунт TestSandbox.*) — без цього рядка «Очистити
        // пісочницю» лишала б годинник trial іти далі
        TrialAnchor.reset()
        #endif
        return true
    }
}

// MARK: - Налаштування застосунку

/// Єдина точка доступу до UserDefaults у всьому Embar.
///
/// ❗ Правило: у коді застосунку немає `UserDefaults.standard` — є
/// `EmbarDefaults.store`. Один пропущений виклик означав би, що
/// пісочниця пише в реальні налаштування. Виняток лише для читання
/// аргументів запуску (для нього є LaunchArgs).
///
/// У SwiftUI те саме робить `.defaultAppStorage(EmbarDefaults.store)` на
/// корені кожної hosting-в'юхи — без нього `@AppStorage` пішов би в
/// `.standard` в обхід усього цього.
enum EmbarDefaults {
    /// Суїт для юніт-тестів: під xcodebuild test прапорця пісочниці
    /// немає, і store був би РЕАЛЬНИМИ налаштуваннями застосунку - тести
    /// сіяча чистили їх у setUp, а обірваний прогін не встигав повернути
    /// (ревʼю 2026-08-12 №6: губився onboardingSeededStickerIDs, і
    /// кнопка «прибрати навчальні стіки» зникала назавжди). Той самий
    /// детектор, що в AppDelegate: клас XCTestCase існує лише в тестах
    static let testSuiteName = "nechai.Embar.UnitTests"

    // MARK: - Наскрізні override-и процесу (argument domain)
    //
    // Єдине, крім LaunchArgs, законне торкання UserDefaults.standard —
    // тому воно живе САМЕ тут, у файлі-власнику межі пісочниці
    // (DefaultsIsolationGuardTests пускає .standard лише сюди).

    /// Покласти ключі у volatile argument domain процесу: система читає
    /// його ПЕРШИМ (раніше за домен застосунку і глобальні), живе він
    /// лише в памʼяті й на диск не потрапляє ніколи. Тож override діє
    /// однаково у звичайному режимі і в пісочниці — не написавши ЖОДНОГО
    /// байта в реальні налаштування (SPEC §15.54: AppleHighlightColor,
    /// AppleAccentColor).
    ///
    /// Наявний вміст домену (розібрані аргументи запуску) зберігається —
    /// setVolatileDomain замінює домен цілком, тому спершу зливаємо.
    static func injectProcessOverrides(_ values: [String: Any]) {
        let defaults = UserDefaults.standard
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in values { domain[key] = value }
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// Підпис, яким наш механізм виділення позначає СВОЄ значення
    /// (формат macOS «R G B Назва» — див. EmbarSelection.highlightValue)
    static let leftoverSignature = "Embar"

    /// Чи можна стирати значення з реального домену. Винесено окремою
    /// чистою функцією, бо ціна помилки тут — чужі налаштування, а
    /// `UserDefaults.standard` юніт-тестом не поганяєш
    /// (SelectionLeftoverTests).
    ///
    /// Два запобіжники (ревʼю 2026-08-18, знахідка 9):
    /// · **пісочниця не пише в реальний домен ніколи** — інваріант
    ///   CLAUDE.md не має винятків, і дебаг-режим не привід його гнути;
    /// · **стираємо лише СВОЄ** — значення, що закінчується нашим
    ///   підписом. Якщо людина колись свідомо зробить
    ///   `defaults write nechai.Embar AppleHighlightColor …`, її вибір
    ///   переживе запуск.
    ///
    /// Одноразовість виходить сама: прибравши свій залишок, ми більше
    /// нічого не знаходимо — окремий прапорець-міграція лише додав би
    /// зайвий ключ у справжні налаштування назавжди.
    static func shouldRemoveLeftover(value: String?, isSandbox: Bool) -> Bool {
        guard !isSandbox, let value else { return false }
        return value.hasSuffix(leftoverSignature)
    }

    /// Прибрати ключ із РЕАЛЬНОГО домену застосунку. Єдиний легальний
    /// вжиток — прибирання за собою: перша версія механізму виділення
    /// (2026-08-17) персистила AppleHighlightColor у справжні
    /// налаштування; тепер значення живе у volatile-домені, а залишок
    /// треба стерти. Умови — у shouldRemoveLeftover вище
    static func removeLeftoverFromRealDomain(key: String) {
        // Пісочниця реального домену не торкається — навіть читанням
        guard !SandboxEnvironment.isActive else { return }
        let value = UserDefaults.standard.string(forKey: key)
        guard shouldRemoveLeftover(value: value, isSandbox: false) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    static let store: UserDefaults = {
        if NSClassFromString("XCTestCase") != nil,
           let suite = UserDefaults(suiteName: testSuiteName) {
            return suite
        }
        guard SandboxEnvironment.isActive else { return .standard }
        guard let suite = UserDefaults(
            suiteName: SandboxEnvironment.defaultsSuiteName) else {
            // Свідомо падаємо: мовчазний відкат на .standard означав би,
            // що пісочниця пише в реальні налаштування — рівно те, чого
            // цей режим має не допустити
            fatalError("Пісочниця: не вдалося відкрити суїт налаштувань")
        }
        return suite
    }()
}
