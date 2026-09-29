//
//  SandboxIsolationTests.swift
//  EmbarTests
//
//  Тестове середовище (`-EmbarTestSandbox`) НЕ МАЄ ПРАВА зачепити
//  реальні дані. Ціна помилки — записи користувача, тому межа
//  перевіряється тестом, а не «на око».
//
//  Тести бігають БЕЗ прапорця пісочниці, тож перевіряють дві речі:
//  1. що звичайний режим лишився звичайним (store === standard);
//  2. що самі механізми ізоляції справді ізолюють — суїт не бачить
//     домену застосунку, шлях бази інший, а всі руйнівні команди без
//     прапорця відмовляються працювати.
//

import XCTest
import SwiftData
@testable import Embar

final class SandboxIsolationTests: XCTestCase {

    /// Тимчасовий суїт для перевірки самої механіки; справжній суїт
    /// пісочниці тест не чіпає
    private let probeSuite = "nechai.Embar.TestSandbox.probe"
    private let probeKey = "sandboxIsolationProbe"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: probeKey)
        UserDefaults.standard.removePersistentDomain(forName: probeSuite)
        super.tearDown()
    }

    // MARK: - Звичайний режим лишається звичайним

    func testUnitTestsUseOwnSuite() {
        XCTAssertFalse(SandboxEnvironment.isActive,
                       "тести не мають бігати з прапорцем пісочниці")
        // Під тестами store - ОКРЕМИЙ суїт (ревʼю №6): раніше це був
        // .standard, і тести сіяча чистили реальні налаштування
        XCTAssertFalse(EmbarDefaults.store === UserDefaults.standard,
                       "тести не сміють писати в реальні налаштування")
        // Пишеться в суїт, не в standard
        let key = "unitSuiteProbe"
        EmbarDefaults.store.set("X", forKey: key)
        XCTAssertNil(UserDefaults.standard.string(forKey: key),
                     "запис у тестовий суїт долетів до реальних налаштувань")
        EmbarDefaults.store.removeObject(forKey: key)
    }

    // MARK: - Суїт не бачить реальних налаштувань

    func testSuiteIsIsolatedFromAppDomain() {
        guard let suite = UserDefaults(suiteName: probeSuite) else {
            return XCTFail("суїт не створився")
        }
        // Реальне значення → пісочниця його НЕ бачить
        UserDefaults.standard.set("REAL", forKey: probeKey)
        XCTAssertNil(suite.string(forKey: probeKey),
                     "суїт пісочниці не мусить читати домен застосунку")

        // Значення пісочниці → реальні налаштування не змінились
        suite.set("SANDBOX", forKey: probeKey)
        XCTAssertEqual(suite.string(forKey: probeKey), "SANDBOX")
        XCTAssertEqual(UserDefaults.standard.string(forKey: probeKey), "REAL",
                       "запис у пісочницю не мусить долітати до реальних налаштувань")
    }

    func testSandboxSuiteNameIsNotAppDomain() {
        let bundleID = Bundle.main.bundleIdentifier ?? "nechai.Embar"
        XCTAssertNotEqual(SandboxEnvironment.defaultsSuiteName, bundleID,
                          "збіг із bundle id означав би той самий домен")
        XCTAssertNotEqual(SandboxEnvironment.defaultsSuiteName,
                          UserDefaults.globalDomain)
    }

    // MARK: - База лежить окремо

    func testStoreURLIsSeparateFromRealStore() {
        let sandbox = SandboxEnvironment.storeURL
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)
        let real = support?.appendingPathComponent("default.store")

        XCTAssertNotEqual(sandbox.path, real?.path)
        XCTAssertEqual(sandbox.deletingLastPathComponent().lastPathComponent,
                       SandboxEnvironment.folderName,
                       "база пісочниці мусить лежати у власній підпапці")
        // Реальне сховище — НЕ всередині теки пісочниці
        if let real {
            XCTAssertFalse(real.path.hasPrefix(SandboxEnvironment.directoryURL.path))
        }
    }

    // MARK: - Руйнівні команди без прапорця не працюють

    func testWipeRefusesWithoutFlag() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let before = try FileManager.default.contentsOfDirectory(atPath: support.path)

        XCTAssertFalse(try SandboxEnvironment.wipe(),
                       "wipe без прапорця мусить відмовитись")

        let after = try FileManager.default.contentsOfDirectory(atPath: support.path)
        XCTAssertEqual(before.sorted(), after.sorted(),
                       "wipe без прапорця не сміє нічого видалити")
    }

    @MainActor
    func testDebugCommandsRefuseWithoutFlag() throws {
        // Контейнер у памʼяті: навіть якби команди спрацювали, до диска
        // вони б не дійшли — але вони й не мусять спрацювати
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(schema: EmbarApp.schema,
                                               isStoredInMemoryOnly: true))
        let context = container.mainContext

        XCTAssertFalse(SandboxDebug.seedStress(10, in: context),
                       "стрес-посів поза пісочницею мусить відмовитись")
        XCTAssertFalse(SandboxDebug.resetOnboarding(in: context),
                       "скидання онбордингу поза пісочницею мусить відмовитись")
        let count = try context.fetchCount(FetchDescriptor<Sticker>())
        XCTAssertEqual(count, 0, "відмова означає, що нічого не створено")
    }

    // MARK: - Розбір аргументів запуску

    func testLaunchArgsParsing() {
        XCTAssertTrue(LaunchArgs.flag("A", in: ["app", "-A", "YES"]))
        XCTAssertTrue(LaunchArgs.flag("A", in: ["app", "-A"]), "голий прапорець = увімкнено")
        XCTAssertTrue(LaunchArgs.flag("A", in: ["app", "-A", "-B", "YES"]),
                      "наступний аргумент — інший прапорець, не значення")
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-A", "NO"]))
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-A", "0"]))
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-B", "YES"]))
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app"]))
        // Не плутати з іншим прапорцем, що починається так само
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-AB", "YES"]))

        // Xcode може віддати «-Name YES» одним рядком, а не двома
        XCTAssertTrue(LaunchArgs.flag("A", in: ["app", "-A YES"]))
        XCTAssertTrue(LaunchArgs.flag("A", in: ["app", "-A=1"]))
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-A NO"]))
        XCTAssertFalse(LaunchArgs.flag("A", in: ["app", "-AB YES"]),
                       "інший прапорець із тим самим початком")

        XCTAssertEqual(LaunchArgs.int("N", in: ["app", "-N", "5000"]), 5000)
        XCTAssertEqual(LaunchArgs.int("N", in: ["app", "-N 5000"]), 5000)
        XCTAssertEqual(LaunchArgs.int("N", in: ["app", "-N=5000"]), 5000)
        XCTAssertNil(LaunchArgs.int("N", in: ["app", "-N", "багато"]))
        XCTAssertNil(LaunchArgs.int("N", in: ["app"]))
    }
}
