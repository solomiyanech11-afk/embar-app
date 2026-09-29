//
//  OnboardingStore.swift
//  Embar
//
//  Прапорці онбордингу — одне місце правди, щоб «чи показувати
//  знайомство» і «чи вже сіяли навчальні стіки» не розповзлись по коду.
//
//  Два НЕЗАЛЕЖНІ прапорці — свідомо:
//  · onboardingCompleted — чи людина вже бачила три такти знайомства;
//    його скидає рядок у Settings («Показати знайомство знову»);
//  · onboardingStickersSeeded — чи стіки-тутоаріал уже сідали на стіну.
//    Стіки сідають РІВНО ОДИН РАЗ за життя застосунку: вони звичайні,
//    їх видаляють і виконують як усі — і повертатись вони не мають.
//
//  Тому повторний показ знайомства з Settings стіки НЕ пересіює.
//

import Foundation

enum OnboardingStore {
    static let completedKey = "onboardingCompleted"
    static let stickersSeededKey = "onboardingStickersSeeded"
    static let noteSeededKey = "onboardingNoteSeeded"
    static let notebookSeededKey = "onboardingNotebookSeeded"

    // MARK: - Показ знайомства

    static var isCompleted: Bool {
        get { EmbarDefaults.store.bool(forKey: completedKey) }
        set { EmbarDefaults.store.set(newValue, forKey: completedKey) }
    }

    /// Чи піднімати вікно знайомства при цьому запуску
    static var shouldRun: Bool { !isCompleted }

    // MARK: - Міграція для наявних користувачів (code review 2026-08-12)

    /// Прапорець зʼявився пізніше за перших користувачів. Без міграції
    /// КОЖЕН, хто оновився, отримав би знайомство примусово: панель не
    /// зʼявляється при старті, замість неї - картка з питанням про імʼя.
    /// Людина з даними Embar уже знає; знайомство - для порожнього
    /// застосунку. Викликати ДО shouldRun.
    static func migrateExistingUserIfNeeded(hasAnyUserData: Bool) {
        guard !isCompleted, hasAnyUserData else { return }
        isCompleted = true
        // Навчальний контент такому користувачу теж не потрібен - його
        // сіячі й так пропустять (дані є), але прапорці ставимо явно,
        // щоб рішення не залежало від порядку викликів
        stickersSeeded = true
        noteSeeded = true
        notebookSeeded = true
        // І ореол шестерні: людина з даними шестерню вже знаходила
        EmbarDefaults.store.set(true, forKey: SettingsGlow.storageKey)
        NSLog("Embar: онбординг пропущено - користувач з наявними даними")
    }

    /// Знайомство пройдено АБО пропущено — з точки зору прапорця це
    /// одне й те саме: більше не показуємо, поки не попросять
    static func complete() { isCompleted = true }

    /// Settings → «Показати знайомство знову». Скидає ЛИШЕ показ
    static func replay() { isCompleted = false }

    // MARK: - Стіки-тутоаріал

    static var stickersSeeded: Bool {
        get { EmbarDefaults.store.bool(forKey: stickersSeededKey) }
        set { EmbarDefaults.store.set(newValue, forKey: stickersSeededKey) }
    }

    /// Навчальна нотатка — власний прапорець і власна умова (нуль нотаток)
    static var noteSeeded: Bool {
        get { EmbarDefaults.store.bool(forKey: noteSeededKey) }
        set { EmbarDefaults.store.set(newValue, forKey: noteSeededKey) }
    }

    /// Навчальний блокнот Рідера — власний прапорець (порожня полиця)
    static var notebookSeeded: Bool {
        get { EmbarDefaults.store.bool(forKey: notebookSeededKey) }
        set { EmbarDefaults.store.set(newValue, forKey: notebookSeededKey) }
    }

    // MARK: - Дебаг

    /// `Embar -ResetOnboarding YES` — прогнати онбординг ще раз із нуля.
    /// Читається з командного рядка (той самий прийом, що в debug-стендах
    /// Embar/Debug/): аргумент живе лише для цього запуску, а прапорці ми
    /// скидаємо назовсім
    static var isResetRequested: Bool {
        LaunchArgs.flag("ResetOnboarding")
    }

    /// Викликати першим у applicationDidFinishLaunching.
    ///
    /// ❗ ЛИШЕ в пісочниці (code review 2026-08-12): скидання прапорців
    /// веде до removeSeeded(), який ФІЗИЧНО видаляє стіки за збереженими
    /// id - включно з тими, що людина вже переписала на власний вміст.
    /// На реальному профілі це стерло б дані повз правило soft-delete.
    /// Той самий guard, що в кожній команді SandboxDebug
    static func applyLaunchArgumentIfNeeded() {
        guard isResetRequested else { return }
        guard SandboxEnvironment.isActive else {
            NSLog("Embar: -ResetOnboarding проігноровано - працює лише з -EmbarTestSandbox")
            return
        }
        isCompleted = false
        stickersSeeded = false
        noteSeeded = false
        notebookSeeded = false
        // Ореол шестерні - теж підказка першого запуску
        EmbarDefaults.store.set(false, forKey: SettingsGlow.storageKey)
        NSLog("Embar: онбординг скинуто (-ResetOnboarding YES)")
    }
}
