//
//  AppDelegateCurrentTests.swift
//  EmbarTests
//
//  Пастка 2026-09-17: під @NSApplicationDelegateAdaptor делегатом
//  застосунку стоїть проксі SwiftUI.AppDelegate, і каст
//  `NSApp.delegate as? AppDelegate` ЗАВЖДИ nil. Через нього тихо не
//  працювали deep-link зі сповіщення на холодному старті, «Показати
//  знайомство знову» і фолбек панелі в онбордингу. Три шляхи переведено
//  на AppDelegate.current - і цей тест тримає обидві половини факту:
//  каст мертвий, а наш init під адаптором таки виконується.
//

import AppKit
import XCTest
@testable import Embar

final class AppDelegateCurrentTests: XCTestCase {

    /// Хост-застосунок тестів - той самий Embar із тим самим адаптором:
    /// якщо SwiftUI перестане кликати наш init, це впаде тут, а не в
    /// людини при кліку по сповіщенню
    func testCurrentIsSetByAdaptor() {
        XCTAssertNotNil(AppDelegate.current,
                        "AppDelegate.current порожній - три шляхи знову мертві")
    }

    /// Документує пастку: якщо колись каст запрацює, можна спростити
    /// назад, але ЛИШЕ свідомо
    func testDelegateCastIsStillDead() {
        XCTAssertNil(NSApp.delegate as? AppDelegate,
                     "NSApp.delegate тепер наш клас? Перевір адаптор перед спрощенням")
    }
}
