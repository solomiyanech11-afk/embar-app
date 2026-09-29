//
//  AppLanguage.swift
//  Embar
//
//  Вибір мови інтерфейсу в Settings (SPEC §6.4).
//
//  Механізм — стандартний для macOS: override ключа `AppleLanguages`
//  у домені застосунку. Система читає його при старті, тому зміна
//  застосовується ЛИШЕ після перезапуску — інакше довелося б
//  перебудовувати весь Bundle на льоту, а NSTextView/NSMenu/сповіщення
//  все одно лишились би старою мовою.
//
//  «Як у системі» ПРИБИРАЄ override, а не копіює поточну мову системи:
//  інакше застосунок назавжди застряг би на тій мові, яка була в момент
//  вибору, і не поїхав би за зміною мови macOS.
//

import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, uk, en

    var id: String { rawValue }

    /// Код локалізації для `AppleLanguages`; nil у «як у системі»
    var code: String? { self == .system ? nil : rawValue }

    /// Назва в списку. Мови підписані ВЛАСНОЮ мовою («English» лишається
    /// «English» і в українському інтерфейсі) — так їх упізнають ті,
    /// хто поточної мови не читає.
    var title: LocalizedStringKey {
        switch self {
        case .system: "Як у системі"
        case .uk: "Українська"
        case .en: "English"
        }
    }
}

enum LanguageStore {
    /// Ключ, який читає система при старті
    private static let appleLanguages = "AppleLanguages"
    /// Наш власний ключ — джерело правди для UI. Окремий, бо
    /// `UserDefaults.object(forKey: "AppleLanguages")` зливає всі домени
    /// й завжди щось повертає, тож із нього не видно, чи є САМЕ наш override.
    private static let choiceKey = "appLanguage"

    /// Мови, які застосунок реально містить
    static var supported: [String] { ["uk", "en"] }

    // MARK: - Вибір

    static var selected: AppLanguage {
        get {
            guard let raw = EmbarDefaults.store.string(forKey: choiceKey),
                  let lang = AppLanguage(rawValue: raw) else { return .system }
            return lang
        }
        set {
            let defaults = EmbarDefaults.store
            defaults.set(newValue.rawValue, forKey: choiceKey)
            if let code = newValue.code {
                defaults.set([code], forKey: appleLanguages)
            } else {
                defaults.removeObject(forKey: appleLanguages)
            }
            // Новий процес читає диск — дотискаємо перед перезапуском
            defaults.synchronize()
        }
    }

    // MARK: - Чи потрібен перезапуск

    /// Мова, якою застосунок працює ЗАРАЗ
    static var activeCode: String {
        Bundle.main.preferredLocalizations.first ?? "uk"
    }

    /// Мова, якою він працюватиме після перезапуску з таким вибором
    static func resolvedCode(for language: AppLanguage) -> String {
        if let code = language.code { return code }
        // «Як у системі»: питаємо ГЛОБАЛЬНИЙ домен, а не власний — інакше
        // побачили б свій же щойно записаний override
        let systemPreferences = EmbarDefaults.store
            .persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguages] as? [String]
        return Bundle.preferredLocalizations(from: supported,
                                             forPreferences: systemPreferences).first ?? "uk"
    }

    /// Вибір справді змінить мову — є сенс питати про перезапуск
    static func changesLanguage(to language: AppLanguage) -> Bool {
        resolvedCode(for: language) != activeCode
    }

    // MARK: - Чистий перезапуск

    /// Піднімає НОВИЙ екземпляр і гасить поточний. Саме в такому порядку:
    /// terminate() першим убив би процес до того, як система встигне
    /// прийняти запит на запуск.
    @MainActor static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // Пісочниця мусить пережити перезапуск (P2.28): без аргумента
        // новий екземпляр піднявся б у РЕАЛЬНИХ даних - зміна мови або
        // wipe із пульта тихо виводили тестовий прогін на справжню базу.
        // Передаємо ЛИШЕ прапорець пісочниці: одноразові команди
        // (-SandboxWipe, -SandboxSeedStress) повторюватись не мають
        if SandboxEnvironment.isActive {
            configuration.arguments = ["-" + SandboxEnvironment.flagName, "YES"]
        }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
