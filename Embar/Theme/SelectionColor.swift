//
//  SelectionColor.swift
//  Embar
//
//  Виділення тексту, каретка і per-app акцент — НАШІ у всьому застосунку,
//  незалежно від Системних налаштувань людини (SPEC §15.54; розслідування
//  2026-08-17 після двох невдалих спроб).
//
//  Чому попередні спроби не діяли:
//  · AccentColor-асет на macOS застосовується ЛИШЕ коли в користувача
//    акцент «Multicolor»; явно вибраний системний акцент завжди перемагає
//    (виміряно: controlAccentColor = системний фіолетовий при заповненому
//    асеті). Тому каретки полів ішли за системою.
//  · Запис AppleHighlightColor у домен застосунку працював, але ПИСАВ у
//    реальні налаштування — а в пісочниці EmbarDefaults.store це окремий
//    суїт, якого NSColor не читає, тож у тестовій схемі ефект тримався
//    лише на випадковому залишку від запуску в звичайному режимі.
//
//  Тепер обидва ключі їдуть у VOLATILE ARGUMENT DOMAIN процесу
//  (EmbarDefaults.injectProcessOverrides): система читає його першим,
//  живе він тільки в памʼяті — працює і в пісочниці, і в звичайному
//  режимі, не торкаючись диска взагалі.
//
//  · AppleHighlightColor → заливка виділення у ВСІХ полях (і тих, що
//    малює field editor / SwiftUI — перевірено піксель-пробою живого
//    NSTextField: #DEDDDA).
//  · AppleAccentColor = "0" → per-app акцент стає пресет-червоним
//    #FF5257 — візуальним близнюком brandRed #FE3B43. Це фарбує каретку
//    в TextEditor тіла стіка (недосяжну інакше без власної обгортки —
//    BACKLOG «точний brandRed у тілі стіка») і фокус-рінги. Виміряно
//    тестом `-AppleAccentColor 0`.
//  · Каретка в усіх TextField — ТОЧНИЙ brandRed 2pt через спільний
//    field editor вікна (EmbarFieldEditor нижче): системні поля редагує
//    не видима вьюха, а field editor, тож фарбувати треба саме його.
//
//  ⚠️ Чому в тону виділення ДВА значення: AppleHighlightColor не має
//  альфи («R G B»). Тому:
//  · `flattened` — непрозорий тон (той самий, змішаний із папером
//    панелі) для полів, де малює система;
//  · `tint` — напівпрозорий для НАШИХ вьюх (тіло нотатки, записи
//    рідера): під виділенням там лежать пастельні хайлайти, і непрозора
//    заливка їх би затерла.
//  На папері обидва виглядають однаково, шва не видно.
//
//  ⚠️ ТОН ЗМІНЕНО 2026-08-20 (рішення користувача, зі скріншотами):
//  акцентний червоний #FF5257, а не тепле графітове чорнило.
//
//  Причина не смакова, а механічна. Виділення в застосунку малюють ТРИ
//  різні шляхи, і виявилось, що вони розходяться:
//  · наші вьюхи (тіло нотатки, записи рідера) — самі, тоном звідси;
//  · поля (TextField через field editor) — система, за AppleHighlightColor;
//  · тіло стіка (SwiftUI TextEditor) — за АКЦЕНТОМ, і на
//    AppleHighlightColor йому байдуже.
//  Тобто стік малював рожеве від пресет-акценту «0» (#FF5257), а решта —
//  графіт: різнобій, який видно неозброєним оком. Зводимо всіх на той
//  тон, який стік показує однаково, — акцентний червоний.
//
//  ❗ Попереднє рішення (§15.54, графіт) відхиляло червоне через
//  сусідство з червоним хайлайтом пера #f4c8c8. Ризик лишається, і його
//  прийнято свідомо: виділення напівпрозоре, тож на хайлайті воно його
//  ПРИТЕМНЮЄ, а не зливається — «виділене підсвічене» відрізняється від
//  просто підсвіченого.
//

import AppKit
import SwiftUI

enum EmbarSelection {
    /// Базовий тон виділення — акцентний червоний, ТОЧНО той, яким
    /// SwiftUI малює виділення в тілі стіка (пресет-акцент «0», див.
    /// applyAppWide). Береться константою, а не з `controlAccentColor`:
    /// системний колір резолвиться від першого читання і в офскрин-
    /// рендері (тести, SandboxShot) міг би приїхати іншим
    private static let accentHex = "#FF5257"

    /// Наскільки густе виділення. ⚠️ ЄДИНЕ місце, де це крутиться:
    /// підбиралось на око до стіка, бо в SwiftUI густину не спитаєш
    private static let alpha: CGFloat = 0.25

    /// Напівпрозоре виділення для власних текстових вьюх
    static let tint = NSColor(embarHex: accentHex).withAlphaComponent(alpha)

    /// «Тихе» виділення: вьюха не first responder АБО вікно не key
    /// (перемкнулись на іншу програму).
    ///
    /// ❗ Це системний сірий, а не наш блідий червоний, і це навмисно:
    /// у полях і в тілі стіка малює система, і там тихий стан виглядає
    /// саме так. Свій відтінок означав би, що нотатка знову єдина не
    /// така, як усі (фідбек 2026-08-21).
    ///
    /// Обчислюваний, не `let`: семантичний колір резолвиться під
    /// ОФОРМЛЕННЯ в момент малювання. Знімок у статичній властивості
    /// застиг би на тому, що діяло при першому читанні
    static var inactive: NSColor { .unemphasizedSelectedTextBackgroundColor }

    /// `tint`, змішаний із поверхнею панелі `#fcfbf9` — непрозорий
    /// двійник для системного малювання (AppleHighlightColor альфи не має)
    static let flattened = flatten(tint, over: NSColor(embarHex: "#fcfbf9"))

    /// Змішати напівпрозорий тон із непрозорим тлом
    private static func flatten(_ top: NSColor, over bottom: NSColor) -> NSColor {
        guard let t = top.usingColorSpace(.sRGB),
              let b = bottom.usingColorSpace(.sRGB) else { return top }
        let a = t.alphaComponent
        return NSColor(srgbRed: t.redComponent * a + b.redComponent * (1 - a),
                       green: t.greenComponent * a + b.greenComponent * (1 - a),
                       blue: t.blueComponent * a + b.blueComponent * (1 - a),
                       alpha: 1)
    }

    /// Чи виділення в цій вьюсі «гучне». Правило те саме, за яким живе
    /// система: мало бути first responder — треба ще й щоб ВІКНО було
    /// key.
    ///
    /// ❗ Без перевірки вікна наші вьюхи лишались яскравими, коли людина
    /// перемикалась на іншу програму, а стіки поруч тихішали — «в
    /// нотатках обирає іншим інструментом» (фідбек 2026-08-21).
    static func isEmphasized(_ view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return window.isKeyWindow && window.firstResponder === view
    }

    /// Перемальовувати виділення, коли вікно стає/перестає бути key.
    /// Сам по собі цей перехід вьюху не інвалідує, тож без підписки
    /// колір мінявся б аж при наступному малюванні з іншої причини.
    /// Повертає токени спостерігача — тримати до смерті вьюхи
    @MainActor
    static func observeKeyChanges(for view: NSView) -> [NSObjectProtocol] {
        guard let window = view.window else { return [] }
        return [NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak view] _ in
                    MainActor.assumeIsolated { view?.needsDisplay = true }
                }
        }
    }

    /// Рядок формату macOS: «R G B Назва» (компоненти 0…1). Назва —
    /// спільний підпис: за ним прибирання впізнає СВОЄ значення і не чіпає
    /// чуже (EmbarDefaults.shouldRemoveLeftover)
    static var highlightValue: String {
        guard let c = flattened.usingColorSpace(.sRGB) else { return "" }
        return String(format: "%.6f %.6f %.6f %@",
                      c.redComponent, c.greenComponent, c.blueComponent,
                      EmbarDefaults.leftoverSignature)
    }

    /// Викликати ОДИН раз, якомога раніше (EmbarApp.init): NSColor кешує
    /// системні кольори при першому читанні, тож override має стояти до
    /// будь-якого малювання.
    static func applyAppWide() {
        var overrides: [String: Any] = [:]
        if !highlightValue.isEmpty {
            overrides["AppleHighlightColor"] = highlightValue
        }
        // Пресет 0 = червоний (рядком — рівно так значення приходить із
        // командного рядка, перевірений шлях)
        overrides["AppleAccentColor"] = "0"
        EmbarDefaults.injectProcessOverrides(overrides)

        // Прибирання за собою: перша версія механізму персистила ключ у
        // реальний домен застосунку (ідемпотентно, ключ був наш)
        EmbarDefaults.removeLeftoverFromRealDomain(key: "AppleHighlightColor")
    }
}

// MARK: - Гасник системної заливки виділення

/// Layout manager для наших текстових вьюх, який НІКОЛИ не малює
/// системну заливку виділення — ні активну, ні «тиху».
///
/// Чому не вистачило `selectedTextAttributes = [.backgroundColor: .clear]`
/// (ревʼю 2026-08-18, знахідка 1): ці атрибути AppKit бере, лише поки
/// вьюха — first responder. Щойно фокус ішов у поле назви (або панель
/// втрачала key), система знову малювала свій
/// `unemphasizedSelectedTextBackgroundColor` — на ВСЮ рядкову коробку
/// разом із зайвим простором від `lineHeightMultiple`, тобто рівно той
/// грубий артефакт, заради якого власне малювання й робилось.
///
/// `fillBackgroundRectArray` — єдина точка, крізь яку проходить БУДЬ-ЯКА
/// заливка тла тексту (і виділення в обох станах теж). Гасимо її тут —
/// і жоден стан фокуса вже не має шляху намалювати щось повз нас.
///
/// ❗ Наслідок: атрибут `.backgroundColor` у тексті теж не малюватиметься.
/// В Embar його немає — усі заливки (хайлайти, чіпи-згадки, риски цитат,
/// виділення) ми малюємо самі в `draw(_:)`. Якщо колись знадобиться —
/// малювати теж вручну, а не вмикати цей шлях назад.
final class EmbarSelectionLayoutManager: NSLayoutManager {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        // Свідомо нічого: власне малювання йде в EmbarTextView.drawSelection
        // і PenTextView.drawSnugSelection
    }
}

// MARK: - Спільний field editor: каретка полів = точний brandRed 2pt

/// Редактор усіх NSTextField-полів вікна (SwiftUI TextField у тому
/// числі): текст у полях набирає НЕ видима вьюха, а цей спільний
/// NSTextView. Колір каретки перебито на рівні властивості — AppKit
/// переналаштовує редактор під кожне поле, тож звичайне присвоєння
/// він би затер.
final class EmbarFieldEditor: NSTextView {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md

    override var insertionPointColor: NSColor? {
        get { NSColor(EmbarColors.brandRed) }
        set { _ = newValue }
    }

    /// 2pt, як у тілі нотатки: брендовий на теплому світлому тлі дає
    /// ~3.2:1, і однопіксельний волосок читався блідим
    override func drawInsertionPoint(in rect: NSRect, color: NSColor,
                                     turnedOn flag: Bool) {
        var r = rect
        r.size.width = 2
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    /// Ширша каретка виходить за системну зону інвалідації — без цього
    /// при блиманні лишався б слід (той самий прийом, що в EmbarTextView)
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -2, dy: 0),
                              avoidAdditionalLayout: flag)
    }
}

/// Реєстр редакторів: по одному на вікно. Один NSTextView не може жити
/// у двох вікнах одночасно (панель + віджети на столі), а слабкі ключі
/// прибирають запис разом із закритим вікном віджета
@MainActor
enum BrandFieldEditors {
    private static let cache =
        NSMapTable<NSWindow, EmbarFieldEditor>(keyOptions: .weakMemory,
                                               valueOptions: .strongMemory)

    /// Віддати редактор для вікна (викликається з
    /// windowWillReturnFieldEditor делегатів вікон)
    static func editor(for window: NSWindow) -> EmbarFieldEditor {
        if let existing = cache.object(forKey: window) { return existing }
        let editor = EmbarFieldEditor()
        editor.isFieldEditor = true
        cache.setObject(editor, forKey: window)
        return editor
    }
}
