//
//  EmbarApp.swift
//  Embar
//
//  Created by Solomiia Nechai on 2026-07-02.
//

import SwiftUI
import SwiftData

@main
struct EmbarApp: App {
    /// Вікно-панель створює AppDelegate (NSPanel, SPEC §1.1), а не WindowGroup
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Наскрізні кольори процесу (виділення тексту, per-app акцент) —
    /// НАЙРАНІШЕ, ще до створення будь-яких вікон: NSColor кешує системні
    /// кольори при першому читанні (Theme/SelectionColor.swift)
    init() {
        EmbarSelection.applyAppWide()
        FocusDebugLog.install() // ⚠️ ТИМЧАСОВО (P2.24): no-op поза пісочницею
    }

    /// Схема — всі сутності зі SPEC.md §11 (CloudKit-сумісні з першого дня,
    /// sync у M6). Одним значенням — щоб тести піднімали контейнер
    /// із ТИМИ САМИМИ сутностями. Схема лише з частиною моделей валить
    /// SwiftData на першому ж insert: у Sticker є звʼязки з Wall і Note,
    /// яких у неповній схемі немає (SIGTRAP, знайдено 2026-08-07)
    static let schema = Schema([
        Sticker.self,
        Wall.self,
        Note.self,
        NoteFolder.self,
        NoteImage.self,
        ReaderBook.self,
        ReaderEntry.self,
        Highlight.self,
        ReaderSource.self,
        ReaderTheme.self,
        Todo.self,
        Habit.self,
        Event.self,
        HomeTag.self,
    ])

    /// Єдиний контейнер даних застосунку
    static let sharedModelContainer: ModelContainer = {
        let schema = Self.schema
        // Тестове середовище (`-EmbarTestSandbox`) працює на ОКРЕМОМУ файлі
        // бази — реальне сховище при цьому не відкривається взагалі
        let modelConfiguration: ModelConfiguration
        if SandboxEnvironment.isActive {
            try? SandboxEnvironment.prepareDirectory()
            modelConfiguration = ModelConfiguration(
                schema: schema, url: SandboxEnvironment.storeURL)
            NSLog("Embar: ПІСОЧНИЦЯ — база \(SandboxEnvironment.storeURL.path)")
        } else {
            modelConfiguration = ModelConfiguration(schema: schema,
                                                    isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Порожня Settings-сцена: головне вікно — NSPanel з делегата
        Settings {
            EmptyView()
        }
    }
}
