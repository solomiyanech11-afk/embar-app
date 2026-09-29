//
//  DebugGuardTests.swift
//  EmbarTests
//
//  Сторож дебаг-інструментів (code review 2026-08-12).
//
//  Історія: -ResetOnboarding не мав guard-а SandboxEnvironment.isActive
//  і на реальному профілі вів до removeSeeded() - ФІЗИЧНОГО видалення
//  стіків за збереженими id, повз правило soft-delete. Кожна команда
//  SandboxDebug такий guard мала, а цей аргумент жив окремо - і його
//  забули.
//
//  Тест робить забування неможливим: сканує вихідники, знаходить КОЖЕН
//  LaunchArgs-прапорець і вимагає, щоб він був класифікований тут -
//  або як нешкідливий (тільки показує/знімає, даних не чіпає), або як
//  руйнівний (тоді поруч мусить стояти guard). Новий дебаг-аргумент,
//  не внесений у жоден список, валить тест і змушує автора свідомо
//  вирішити, чи потрібен запобіжник.
//

import XCTest
@testable import Embar

final class DebugGuardTests: XCTestCase {

    // MARK: - Класифікація прапорців

    /// Нешкідливі: відкривають дебаг-стенд, малюють знімок або міняють
    /// ДОВІДКОВИЙ стан (стиль підказки). Даних користувача не торкаються
    private static let harmless: Set<String> = [
        "GlassLab", "GlassShot", "WidgetTintLab", "WidgetLayoutLab",
        "EmptyStatesLab",
        "SandboxShot", "SandboxShotGlow", "SandboxShotGhost",
        // Дублює PNG знімка в stdout (base64) — лише читає те, що вже
        // намальовано; даних не чіпає
        "SandboxShotBase64",
        // Синтетичне наведення на кнопку закриття перед знімком
        // (2026-09-27): лише читає рамки і постить mouseMoved у власний
        // процес; даних не чіпає
        "SandboxShotHoverClose", "SandboxShotHoverStale",
        // Вимірювальний зонд: лише читає тайминги і скролить/друкує у
        // ВЛАСНІ вікна; активний тільки разом із прапорцем пісочниці
        "SandboxPerfProbe",
        // Зонд палітри емоджі (P2.33): відкриває системну палітру, варпає
        // курсор і пише лог у Documents контейнера; лише пісочниця
        "SandboxEmojiProbe",
        // Показує вікно пейвола для знімків/ітерації дизайну - лише UI,
        // даних не чіпає
        "SandboxShowPaywall",
        // Зонд рівнів вікна під час системного діалогу покупки: лише
        // читає й логує рівні, покупки не робить, даних не чіпає
        "SandboxPaywallDialogProbe",
        // Скинути стан покупки (2026-09-17): чистить лише КЕШ статусу pro
        // (наш і RevenueCat), який RC відновлює з мережі; нотаток не
        // торкається. Свідомо БЕЗ guard-а пісочниці - покупка тестується
        // у звичайному Debug після Clear Purchase History в ASC
        "DebugResetPurchaseState",
        // Сам вмикач пісочниці - він і Є межею
        "EmbarTestSandbox",
    ]

    /// Руйнівні: скидають прапорці, сіють, видаляють. Функція, що їх
    /// читає, мусить мати guard SandboxEnvironment.isActive
    private static let destructive: Set<String> = [
        "ResetOnboarding",
        "SandboxWipe", "SandboxResetOnboarding", "SandboxSeedStress",
        // Демо-дані для маркетингу (DemoSeeder): сіє базу й налаштування,
        // тому пише ЛИШЕ в теку пісочниці — guard стоїть і в
        // runLaunchCommands, і в самому DemoSeeder.seedIfNeeded
        "SandboxSeedDemo",
        // Монетизація (SPEC §15.77): мутують якір trial у Keychain/defaults
        // і кеш статусу pro — стан доступу користувача. Guard стоїть у
        // runLaunchCommands і в кожній команді (resetTrial/shiftTrial/
        // cycleProOverride), а TrialAnchor.shift/reset мають і власний
        "SandboxResetTrial", "SandboxTrialShiftDays", "SandboxProOverride",
    ]

    // MARK: - Скан вихідників

    private var appSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Embar")
        return (FileManager.default.enumerator(at: root,
                                               includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
    }

    /// Усі імена прапорців, які код читає через LaunchArgs
    private func discoveredFlags() throws -> [(name: String, file: String)] {
        var found: [(String, String)] = []
        let pattern = try NSRegularExpression(
            pattern: #"LaunchArgs\.(?:flag|int)\("([A-Za-z]+)""#)
        for file in appSources where file.lastPathComponent != "SandboxEnvironment.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    found.append((String(text[r]), file.lastPathComponent))
                }
            }
        }
        return found
    }

    func testSourcesAreReachable() throws {
        XCTAssertGreaterThan(try discoveredFlags().count, 5,
                             "скан не знайшов прапорців - перевір шлях або регекс")
    }

    /// КОЖЕН прапорець мусить бути класифікований. Новий дебаг-аргумент
    /// без запису тут не пройде CI - і автору доведеться вирішити,
    /// руйнівний він чи ні
    func testEveryFlagIsClassified() throws {
        let known = Self.harmless.union(Self.destructive)
        let unknown = try discoveredFlags().filter { !known.contains($0.name) }
        XCTAssertTrue(unknown.isEmpty, """
            Некласифіковані дебаг-аргументи: \(unknown). Додай кожен у \
            DebugGuardTests.harmless або .destructive - і якщо він руйнівний, \
            постав guard SandboxEnvironment.isActive поруч із читанням.
            """)
    }

    /// Руйнівний прапорець читається лише у файлі, де в тілі тієї ж
    /// функції стоїть guard SandboxEnvironment.isActive
    func testDestructiveFlagsAreGuarded() throws {
        let pattern = try NSRegularExpression(
            pattern: #"LaunchArgs\.(?:flag|int)\("([A-Za-z]+)""#)
        var offenders: [String] = []
        for file in appSources where file.lastPathComponent != "SandboxEnvironment.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            let names = pattern.matches(in: text, range: range).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
            let destructiveHere = names.filter { Self.destructive.contains($0) }
            guard !destructiveHere.isEmpty else { continue }
            // Грубо, але надійно: guard мусить бути в ТОМУ Ж файлі.
            // Функційну гранулярність статично не візьмеш без парсера,
            // а руйнівні читання в нас зібрані по одному на файл
            if !text.contains("SandboxEnvironment.isActive") {
                offenders.append("\(file.lastPathComponent): \(destructiveHere)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Руйнівні дебаг-аргументи без guard SandboxEnvironment.isActive \
            у файлі: \(offenders)
            """)
    }

    // MARK: - Runtime: скидання онбордингу поза пісочницею - no-op

    /// Не лише текст, а й поведінка: навіть якщо прапорець зведено,
    /// поза пісочницею applyLaunchArgumentIfNeeded нічого не чіпає.
    /// (Прапорець процесу тут не зведеш, тож перевіряємо шлях, коли
    /// isResetRequested == false, і головне - що стан не мутується.)
    func testResetOutsideSandboxIsNoOp() {
        XCTAssertFalse(SandboxEnvironment.isActive,
                       "тести не мають бігати з прапорцем пісочниці")
        let before = (OnboardingStore.isCompleted,
                      OnboardingStore.stickersSeeded,
                      OnboardingStore.noteSeeded,
                      OnboardingStore.notebookSeeded)
        OnboardingStore.applyLaunchArgumentIfNeeded()
        let after = (OnboardingStore.isCompleted,
                     OnboardingStore.stickersSeeded,
                     OnboardingStore.noteSeeded,
                     OnboardingStore.notebookSeeded)
        XCTAssertTrue(before == after, "скидання поза пісочницею мутувало прапорці")
    }
}
