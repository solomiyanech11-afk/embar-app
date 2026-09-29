//
//  PaywallPriceSourceTests.swift
//  EmbarTests
//
//  Сторож джерела цін (блокер 2026-09-17).
//
//  Історія: для знімків дизайну в пісочниці в моделі жили фейкові ціни
//  ("$2.99"/"$24.99"). Вони підмінювали справжні, і кнопка обіцяла
//  «Get Lifetime for $24.99», поки системний діалог StoreKit показував
//  29,99 USD. Ціна на пейволі мусить приходити ВИКЛЮЧНО зі StoreKit
//  (localizedPriceString пакета) - жодних власних знаків валюти,
//  форматування чи фолбеків із цифрою. Немає ціни - це офлайн-стан,
//  а не вигадана ціна.
//
//  Тест сканує вихідники пейвола і монетизації: будь-який рядковий
//  літерал, що виглядає як ціна, валить збірку.
//

import XCTest
@testable import Embar

final class PaywallPriceSourceTests: XCTestCase {

    /// Файли, де цінам узагалі є місце
    private var paywallSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EmbarTests
            .deletingLastPathComponent()   // корінь
            .appendingPathComponent("Embar")
        let folders = [root.appendingPathComponent("Features/Paywall"),
                       root.appendingPathComponent("Monetization")]
        return folders.flatMap { folder in
            (FileManager.default.enumerator(at: folder,
                                            includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }) ?? []
        }
    }

    private func isComment(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("///")
            || trimmed.hasPrefix("*")
    }

    /// Вміст усіх рядкових літералів у рядку коду
    private func stringLiterals(in line: Substring) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let text = String(line)
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    func testSourcesAreReachable() {
        XCTAssertGreaterThan(paywallSources.count, 3,
                             "скан не знайшов файлів пейвола - перевір шлях")
    }

    /// Жодного знака валюти, ISO-коду чи числа «X.99» у літералах
    func testNoPriceLiteralsInPaywallCode() throws {
        // Знак валюти будь-де в літералі, ISO-код окремим словом,
        // або число з двома десятковими (2.99 / 29,99)
        let suspicious = try NSRegularExpression(
            pattern: #"[$€£¥₴]|\b(?:USD|EUR|GBP|UAH|PLN)\b|\d+[.,]\d{2}"#)
        var offenders: [String] = []
        for file in paywallSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (i, line) in text.split(separator: "\n",
                                        omittingEmptySubsequences: false).enumerated()
            where !isComment(line) {
                for literal in try stringLiterals(in: line) {
                    let range = NSRange(literal.startIndex..., in: literal)
                    if suspicious.firstMatch(in: literal, range: range) != nil {
                        offenders.append("\(file.lastPathComponent):\(i + 1) «\(literal)»")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Літерал ціни у коді пейвола: \(offenders). Ціна приходить \
            ЛИШЕ зі StoreKit (package.localizedPriceString); якщо ціни \
            немає - це офлайн-стан, а не власна цифра чи знак валюти.
            """)
    }

    /// Зворотний бік: ціни таки беруться з пакета StoreKit
    func testPricesComeFromStoreKitPackage() throws {
        let view = paywallSources.first { $0.lastPathComponent == "PaywallView.swift" }
        let text = try String(contentsOf: try XCTUnwrap(view), encoding: .utf8)
        XCTAssertTrue(text.contains("package.localizedPriceString"),
                      "картки і CTA мусять брати ціну з пакета StoreKit")
    }

    /// Окупність lifetime рахується з реальних цін, а не з константи
    func testPayOffPeriodIsComputedFromPrices() throws {
        let model = paywallSources.first { $0.lastPathComponent == "PaywallModel.swift" }
        let text = try String(contentsOf: try XCTUnwrap(model), encoding: .utf8)
        XCTAssertTrue(text.contains("storeProduct.price"),
                      "«окупається за N міс.» мусить рахуватись із цін StoreKit")
    }
}
