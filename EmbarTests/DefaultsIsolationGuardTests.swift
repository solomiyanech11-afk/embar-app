//
//  DefaultsIsolationGuardTests.swift
//  EmbarTests
//
//  Сторож межі пісочниці на рівні ВИХІДНИКІВ.
//
//  Історія: ThemeStore тримав налаштування в @AppStorage. Усередині
//  класу ця обгортка завжди пише в UserDefaults.standard - модифікатор
//  `.defaultAppStorage(...)` живе в оточенні SwiftUI і до звичайного
//  обʼєкта не доходить. Через це в пісочниці палітра, фон панелі й
//  матеріальність писались у РЕАЛЬНІ налаштування (баг 2026-08-11).
//
//  Юніт-тестом це не зловити: у тестах обидва сховища - один і той самий
//  обʼєкт, тож підміна непомітна. Тому перевіряємо самі файли.
//

import XCTest
@testable import Embar

final class DefaultsIsolationGuardTests: XCTestCase {

    /// Корінь репозиторію - від шляху цього файлу під час компіляції
    private var appSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EmbarTests
            .deletingLastPathComponent()   // корінь
            .appendingPathComponent("Embar")
        let files = FileManager.default.enumerator(at: root,
                                                   includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return files
    }

    /// Згадка в коментарі - не використання
    private func isComment(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("///")
            || trimmed.hasPrefix("*")
    }

    func testSourcesAreReachable() {
        XCTAssertGreaterThan(appSources.count, 30,
                             "тест втратив вихідники - перевір шлях")
    }

    /// @AppStorage у КЛАСІ мовчки йде повз пісочницю. У Views він
    /// законний: там працює .defaultAppStorage на корені hosting-вʼюхи
    func testNoAppStorageInsideObservableObjects() throws {
        var offenders: [String] = []
        for file in appSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("ObservableObject") else { continue }
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("@AppStorage") && !line.contains("store:")
                && !isComment(line) {
                offenders.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            @AppStorage без явного store: у файлі з ObservableObject - \
            він писатиме в реальні налаштування повз пісочницю. \
            Використай EmbarDefaults.store: \(offenders)
            """)
    }

    /// Той самий інваріант, що в CLAUDE.md: у коді застосунку немає
    /// прямих звернень до UserDefaults.standard
    func testNoDirectStandardDefaults() throws {
        var offenders: [String] = []
        for file in appSources where file.lastPathComponent != "SandboxEnvironment.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("UserDefaults.standard") && !isComment(line) {
                offenders.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "пряме звернення до UserDefaults.standard повз EmbarDefaults: \(offenders)")
    }
}
