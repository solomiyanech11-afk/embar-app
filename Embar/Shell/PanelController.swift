//
//  PanelController.swift
//  Embar
//
//  AppKit-оболонка панелі: NSPanel, докований до правого краю екрана.
//  Розміри й поведінка — SPEC.md §1.1 і §1:
//  · висота = вся видима висота екрана (NSScreen.visibleFrame)
//  · ширина за замовчуванням = 25% екрана, clamp 340–420pt
//  · ресайз лівим краєм у межах 320–480pt (власна ручка), збереження між запусками
//  · поява: слайд 0.68s + масштаб вмісту 0.94→1 від правого краю + наростання
//    тіні; ховання простіше — слайд 0.24s (крива прототипу). Reduce Motion —
//    фейд без руху й масштабу
//  · edge hover відкриває; відхід миші ховає через 550 мс; lock вимикає autohide
//
//  ПРИСУТНІСТЬ НАД УСІМ (SPEC §1.1): панель і тригер мають працювати над
//  fullscreen-застосунками і на всіх Spaces. Для цього ОБИДВА вікна:
//  · nonactivating NSPanel; тригер borderless, панель - з утилітарною
//    смужкою заголовка (titled + fullSizeContentView, лише червона
//    кнопка закриття - App Review Guideline 4, 2026-09-25, SPEC §15.78).
//    Старе застереження «titled не пускає на fullscreen» стосувалось
//    звичайного NSWindow: nonactivating NSPanel із .fullScreenAuxiliary
//    показується над fullscreen і з заголовковою маскою
//  · hidesOnDeactivate = false (дефолт NSPanel — true: AppKit ховав панель,
//    щойно Embar втрачав активність — тому «працювало лише на робочому столі»)
//  · level .statusBar, collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary]
//

import AppKit
import Combine
import SwiftUI

/// Borderless-панель, який може ставати key-вікном (потрібно для полів вводу)
extension Notification.Name {
    /// Панель показано (hover/хоткей) — композер активної поверхні бере фокус.
    /// userInfo["reason"] — сирий PanelShowReason (потрібен онбордингу, щоб
    /// відрізнити «людина викликала жестом» від автопоказу при старті)
    static let embarPanelDidShow = Notification.Name("embar.panelDidShow")
    /// Панель ховається — текстові поля скидають фокус
    static let embarPanelDidHide = Notification.Name("embar.panelDidHide")
}

/// Чому панель зʼявилась. Для більшості коду байдуже — але онбординг
/// (Такт 2 «наведи мишу на правий край») мусить зарахувати РІВНО дію
/// користувача, а не показ, який застосунок влаштував собі сам
enum PanelShowReason: String {
    /// Автопоказ при старті застосунку
    case launch
    /// Курсор торкнувся смужки-тригера на правому краю
    case edgeHover
    /// Глобальний шорткат (⌥E за замовчуванням)
    case hotkey
    /// Клік по іконці в Dock
    case dockClick
    /// Показ із коду (кнопка «Покажи мені» в онбордингу тощо)
    case programmatic
}

/// Стан появи вмісту панелі: PanelController перемикає його при показі /
/// хованні, а SwiftUI-корінь (PanelRevealEffect) масштабує вміст.
/// Масштабуємо саме ВМІСТ, а не вікно: transform вікна розмиває текст
/// і дорого рендериться; вікно їде лише по позиції
final class PanelRevealState: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = PanelRevealState()
    @Published var revealed = false
}

/// Обгортка SwiftUI-кореня: при появі панелі вміст «доростає» 0.94 → 1.0
/// від правого краю (anchor .trailing) — панель ніби виходить з-за краю
/// екрана, а не пролітає збоку. Reduce Motion вимикає масштаб повністю
/// (лишається фейд вікна, який веде PanelController)
private struct PanelRevealEffect<Content: View>: View {
    @ObservedObject private var reveal = PanelRevealState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content

    var body: some View {
        content.scaleEffect(
            reduceMotion || reveal.revealed ? 1 : 0.94,
            anchor: .trailing)
    }
}

final class EmbarPanel: NSPanel {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    override var canBecomeKey: Bool { true }

    // MARK: - Без select-all при програмному фокусі (P2.24)
    //
    // macOS, віддаючи полю фокус без прямої дії користувача в самому
    // полі (@FocusState, відновлення сесії редагування після «сироти»
    // first responder, показ панелі), виділяє ВЕСЬ текст поля. Відколи
    // виділення акцентно-червоне (§15.54, ревізія 2026-08-20), кожен
    // такий перехідний кадр читається як червоне мигання (олівець
    // редагування запису, чіп «Тема», відкриття блокнота).
    //
    // ❗ Чому саме тут, а не в EmbarFieldEditor: SwiftUI-поля панелі
    // приносять ВЛАСНИЙ field editor (_SystemTextFieldFieldEditor) і
    // обходять windowWillReturnFieldEditor - правило в нашому редакторі
    // до них не доходить (доведено трасою [P224] 2026-09-03, SPEC
    // §15.72). makeFirstResponder вікна - єдиний вузол, через який
    // проходить КОЖНЕ здобуття фокуса будь-яким редактором; згортання
    // тут відбувається в тому ж циклі подій, до коміту кадру.
    //
    // Свідомі шляхи лишаються: Tab (keyDown) тримає системний
    // select-all; подвійний клік (rename теми) - свою семантику
    // «виділити для заміни». ⚠️ Подвійний клік звіряється не з
    // NSApp.currentEvent (фокус приходить тіком пізніше, і currentEvent
    // на той момент може бути вже mouseMoved від ховер-трекінгу), а з
    // власною памʼяттю недавніх подвійних кліків із sendEvent.

    /// Мить останнього подвійного/потрійного кліку (для rename-полів,
    /// що фокусуються тіком пізніше за клік)
    private var lastMultiClickAt: TimeInterval = -1

    /// Скільки памʼятаємо подвійний клік: фокус rename-поля приходить
    /// наступним тіком (<50мс), із запасом на повільний кадр
    private static let multiClickMemory: TimeInterval = 0.6

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount >= 2 {
            lastMultiClickAt = event.timestamp
        }
        super.sendEvent(event)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(responder)
        if FocusDebugLog.enabled {
            FocusDebugLog.log("makeFirstResponder(\(FocusDebugLog.describe(responder))) -> \(ok)")
        }
        // Після super: і виклик з редактором, і виклик із самим полем
        // закінчуються тим, що справжній first responder - field editor
        // (яким би класом він не був), і select-all уже стоїть
        guard ok, let editor = firstResponder as? NSTextView,
              editor.isFieldEditor else { return ok }
        let recentMultiClick = lastMultiClickAt >= 0
            && ProcessInfo.processInfo.systemUptime - lastMultiClickAt
                < Self.multiClickMemory
        let current = NSApp.currentEvent
        let isTabKey = current?.type == .keyDown && current?.keyCode == 48
        if let collapsed = Self.collapsedInitialSelection(
            current: editor.selectedRange(),
            textLength: (editor.string as NSString).length,
            isTabKey: isTabKey,
            recentMultiClick: recentMultiClick) {
            editor.setSelectedRange(collapsed)
            if FocusDebugLog.enabled {
                FocusDebugLog.log("згорнуто початковий select-all → каретка \(collapsed) (той самий цикл подій)")
            }
        }
        return ok
    }

    /// Чисте правило (під тести): nil - виділення лишити як є, інакше -
    /// каретка, якою його замінити
    static func collapsedInitialSelection(current: NSRange, textLength: Int,
                                          isTabKey: Bool,
                                          recentMultiClick: Bool) -> NSRange? {
        // Чіпаємо лише ПОВНЕ виділення непорожнього тексту.
        // ❗ ⌘A сюди не потрапляє взагалі: він не міняє first responder
        guard textLength > 0, current.location == 0,
              current.length == textLength else { return nil }
        // Tab/⇧Tab у поле: фокус їде синхронно в обробці keyDown
        // (currentEvent надійний), системний select-all лишається.
        // Саме Tab, а не будь-який keyDown: фокус, що збігся зі
        // звичайною літерою, не має право лишити виділеною чернетку
        if isTabKey { return nil }
        // Подвійний клік (rename теми): «виділити для заміни» лишається
        if recentMultiClick { return nil }
        return NSRange(location: textLength, length: 0)
    }

    // MARK: - Сесія редагування переживає втрату key (P2.33)
    //
    // Палітра емоджі (Globe+E) - вікно ЧУЖОГО процесу: воно не зʼявляється
    // в NSApp.windows і не стає frontmost, але забирає в панелі key-статус.
    // NSPanel у resignKeyWindow (на відміну від звичайного NSWindow)
    // примусово викликає endEditing(for:) - і field editor SwiftUI-полів
    // здається ще ДО кліку по емоджі, вставці нема куди прийти. Наш
    // NSTextView (тіло нотатки) endEditing не зачіпає - тому в нотатках
    // палітра працювала, а в композері Рідера ні (доведено стеком:
    // _handleKeyFocusNotification → resignKeyWindow → endEditingFor:,
    // зонд EmojiPaletteProbe 2026-09-04).
    //
    // Прибираємо САМЕ цей примус: поки йде resignKey, endEditing - no-op.
    // Усі свідомі завершення редагування (клік в інше поле, ховання панелі
    // через makeFirstResponder(nil), Enter/Tab) ідуть іншими шляхами і
    // лишаються як були.

    private var isResigningKey = false

    override func resignKey() {
        isResigningKey = true
        super.resignKey()
        isResigningKey = false
    }

    override func endEditing(for object: Any?) {
        if isResigningKey {
            if FocusDebugLog.enabled {
                FocusDebugLog.log("endEditing під resignKey пропущено - сесія редагування живе (P2.33)")
            }
            return
        }
        super.endEditing(for: object)
    }

    /// Завжди «key» для рендера: нативний Liquid Glass (і споріднені
    /// ефекти) слідкують за key-станом вікна — скло і його тінь мінялись
    /// між першим показом і кліком у поле (фідбек 2026-07-19). Панель
    /// nonactivating, тож чесного key до кліку не буває; override дає
    /// стабільний «активний» вигляд. Нотифікації resignKey не зачіпає
    override var isKeyWindow: Bool { true }

    /// macOS за замовчуванням не дає вікну виїхати за межі екрана — «повертає»
    /// його назад, через що слайд-анімація зникала. Наша панель свідомо
    /// стартує/ховається за правим краєм.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: - Утилітарна смужка заголовка (SPEC §15.78)

    /// ⌘W / ⌘M у панелі = сховати її (той самий шлях, що червона і жовта
    /// кнопки). Спершу шанс вʼюхам і меню; лишається лише голе ⌘W/⌘M,
    /// яке інакше пискнуло б
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case "w" where styleMask.contains(.closable):
            performClose(nil)
            return true
        case "m" where styleMask.contains(.miniaturizable):
            performMiniaturize(nil)
            return true
        default:
            return false
        }
    }

    /// Жовта кнопка, ⌘M, подвійний клік по смужці (якщо система так
    /// налаштована): панель НЕ згортається в Dock - вона ховається тим
    /// самим слайдом, що при відведенні курсора (SPEC §15.78є). Обидва
    /// шляхи AppKit перекриті: клік по кнопці йде в miniaturize(_:)
    /// напряму, меню/⌘M - через performMiniaturize(_:)
    var onHideRequest: (() -> Void)?
    override func miniaturize(_ sender: Any?) { onHideRequest?() }
    override func performMiniaturize(_ sender: Any?) { onHideRequest?() }

    /// Зелена кнопка / подвійний клік по смужці: НЕ вбудований zoom
    /// AppKit (він затискає рамку у visibleFrame, а панель свідомо стоїть
    /// нижче Dock - висота обрізалась 891 → 837, тест 2026-09-27), а наш
    /// перемикач ширини 320 ↔ 480 (PanelController.zoomWidth)
    var onZoomRequest: (() -> Void)?
    override func zoom(_ sender: Any?) { onZoomRequest?() }
    override func performZoom(_ sender: Any?) { onZoomRequest?() }
}

/// NSView, що повідомляє про вхід/вихід миші (для hover-логіки)
final class HoverView: NSView {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// Ручка ресайзу на лівому краю borderless-панелі (нативний .resizable
/// вимагав .titled, який блокує показ над fullscreen). Тягне лівий край,
/// правий лишається притиснутим; ширина зберігається в UserDefaults.
final class ResizeHandleView: NSView {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    private var startFrame: NSRect = .zero
    private var startMouseX: CGFloat = 0

    /// Драг почався / завершився — панель на цей час замикає auto-hide
    /// (F7: тяга за допустиму межу відводила курсор за панель, і та
    /// ховалась просто під рукою)
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    /// ❗ Курсор-рект програє NSTextView: тіло нотатки виставляє I-beam
    /// динамічно (mouseMoved/cursorUpdate), і смужка ресайзу «зникала» —
    /// заявлені 6pt відчувались як один піксель (P2.3). cursorUpdate від
    /// найвищої вьюхи під курсором цей бій виграє
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    /// Панель зʼявляється по наведенню, застосунок при цьому лишається
    /// неактивним — без цього ПЕРШИЙ клік по ручці лише активував би
    /// застосунок, і перша спроба потягнути не робила нічого (P2.3)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startMouseX = NSEvent.mouseLocation.x
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let dx = NSEvent.mouseLocation.x - startMouseX
        let width = min(max(startFrame.width - dx, PanelController.resizeMin), PanelController.resizeMax)
        window.setFrame(
            NSRect(x: startFrame.maxX - width, y: startFrame.minY,
                   width: width, height: startFrame.height),
            display: true
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer { onDragEnded?() }
        guard let window else { return }
        EmbarDefaults.store.set(Double(window.frame.width), forKey: PanelController.widthKey)
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    // Межі зі SPEC §1.1
    static let resizeMin: CGFloat = 320
    static let resizeMax: CGFloat = 480
    static let defaultClampMin: CGFloat = 340
    static let defaultClampMax: CGFloat = 420
    static let widthKey = "panelWidth"
    static let lockedKey = "panelLocked"   // той самий ключ, що AppStorage-проперті у ContentView
    /// Зазор від країв екрана (верх/низ/право) — панель «левітує», тінь-
    /// туман видно з усіх боків (фідбек 2026-07-19)
    static let edgeInset: CGFloat = 6

    private let panel: EmbarPanel
    private var edgeTrigger: NSPanel?
    private var hideTask: Task<Void, Never>?
    /// Рамка панелі зараз їде (показ або ховання). Поки true, ніхто
    /// сторонній не сміє смикати `setFrame` — інакше рух рветься (P2.1)
    private var isAnimatingFrame = false
    /// Покоління анімації ховання: show() інвалідовує застарілі completion-и,
    /// toggle() під час ховання трактується як «показати» (code review 2026-07-04)
    private var hideGeneration = 0
    private var isHiding = false

    private var isLocked: Bool {
        EmbarDefaults.store.bool(forKey: Self.lockedKey)
    }

    /// Glass-підкладка (blur столу) під SwiftUI-коренем — ретейн-реф,
    /// щоб керувати видимістю за темою
    private var glassBacking: NSView?

    /// Мʼяка тінь-«туман» — ОКРЕМЕ click-through вікно під панеллю
    /// (фідбек 2026-07-19): системна тінь вікна малювала чорний обідок,
    /// а власна тінь усередині вікна панелі блокувала б кліки у прозорому
    /// полі навколо. Дочірнє вікно їздить разом зі слайдом панелі саме.
    private var shadowWindow: NSPanel?
    private var shadowLayer: CALayer?
    /// Запас під розмиття (більший за 2×shadowRadius)
    private static let shadowMargin: CGFloat = 70

    // MARK: - Матеріальність (Glass-тема, DESIGN-DIRECTIONS §1)

    /// Фабрика підкладки: macOS 26+ — нативний Liquid Glass; 14–15 —
    /// NSVisualEffectView(.behindWindow). Скло виносимо у функцію, щоб
    /// гілка 26 була одним місцем (компілюється на будь-якому SDK).
    private static func makeGlassBackingView() -> NSView {
        // TODO(macOS 26 SDK): коли збиратимемо проти SDK 26 — тут
        // NSGlassEffectView за #available(macOS 26, *). До того нативний
        // клас у поточному SDK відсутній, тож fallback усюди.
        let vev = NSVisualEffectView()
        vev.blendingMode = .behindWindow  // blur того, що ПОЗАДУ вікна (стіл)
        vev.state = .active               // ❗ панель nonactivating: без .active
                                          // матеріал «неактивний» і сірий
        vev.material = .popover           // світле «молоко» під pinned .aqua
        vev.wantsLayer = true
        vev.layer?.cornerRadius = 16      // = SwiftUI clipShape(16) кореня
        vev.layer?.masksToBounds = true
        vev.isHidden = true               // вмикає лише Glass у applyMaterialTheme
        return vev
    }

    @objc private func materialChanged() { applyMaterialTheme() }

    /// Ефективна тема з урахуванням Reduce Transparency (§15.17)
    private var effectiveMaterialTheme: MaterialTheme {
        let raw = EmbarDefaults.store.string(forKey: "materialTheme") ?? "opaque"
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return reduce ? .opaque : (MaterialTheme(rawValue: raw) ?? .opaque)
    }

    /// Цільова прозорість тіні-«туману»: у Левітації тінь гасне (обвела б
    /// прозорі зони — острови несуть тінь самі). Анімація появи веде тінь
    /// 0 → саме це значення
    private var shadowTargetAlpha: CGFloat {
        effectiveMaterialTheme == .levitation ? 0 : 1
    }

    /// Показ blur і тінь вікна за поточною темою; Reduce Transparency
    /// примусово опакне (§15.17)
    private func applyMaterialTheme() {
        // Blur потрібен лише Glass; Opaque малює молоко в SwiftUI, Левітація — 0%
        glassBacking?.isHidden = (effectiveMaterialTheme != .glass)
        // Тінь вікна вимкнена НАЗАВЖДИ (2026-07-19): системна тінь малює
        // темний обідок по контуру панелі. Замість неї — вікно-«туман»
        panel.hasShadow = false
        panel.invalidateShadow()
        shadowWindow?.alphaValue = shadowTargetAlpha
    }

    /// Рівень панелі: Dock+1 (21), не .statusBar (25) і не .floating (3):
    /// мінімальний рівень, на якому панель повної висоти ПЕРЕКРИВАЄ Dock
    /// (фідбек 2026-07-19 — на .floating Dock малювався поверх панелі),
    /// але все ще лишається під системним превʼю скріншота, яке
    /// .statusBar накривав. Над fullscreen працює через .fullScreenAuxiliary
    static let panelLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    /// Радіус кута панелі (= SwiftUI clipShape кореня і скло-підкладка)
    static let panelCornerRadius: CGFloat = 16

    /// Вікно панелі з усією поведінкою (фабрика - щоб тест міг перевірити
    /// той самий обʼєкт, що бачить користувач). Порядок важливий: спершу
    /// утилітарна смужка (SPEC §15.78) - зміна styleMask може скинути
    /// рівень/поведінку, тому властивості нижче ставляться ПІСЛЯ неї
    static func makePanelWindow() -> EmbarPanel {
        // Три кнопки (SPEC §15.78є): .miniaturizable вмикає жовту (= сховати,
        // перекрито в EmbarPanel), .resizable - зелену (без нього AppKit
        // тримає її вимкненою і скидає isEnabled при кожному перетилінгу -
        // доведено зондом 2026-09-27). Нативний ресайз краю при цьому
        // блокує windowWillResize; ширину міняє лише наша ручка і zoom
        let panel = EmbarPanel(
            contentRect: .zero,
            styleMask: WindowChrome.utilityMask.union(
                [.nonactivatingPanel, .miniaturizable, .resizable]),
            backing: .buffered,
            defer: false
        )
        WindowChrome.applyUtilityTitlebar(to: panel, title: "Embar", buttons: .all)
        // Кнопка - на діагоналі кута панелі (єдине правило всіх вікон)
        WindowChrome.pinCloseButton(in: panel, cornerRadius: panelCornerRadius)
        // Панель докована до краю: за смужку заголовка її НЕ відтягнути
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.level = panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // БЕЗ тіні вікна: системна тінь малює темний обідок по контуру
        // панелі, який не перекрити зсередини (фідбек 2026-07-19).
        // Панель докована до краю — тінь їй не потрібна
        panel.hasShadow = false
        // Панель завжди світла (#fcfbf9) — фіксуємо світлий appearance, щоб
        // системні елементи не ставали білими в темній темі macOS. Dark mode — M6.
        panel.appearance = NSAppearance(named: .aqua)
        return panel
    }

    init(rootView: some View) {
        panel = Self.makePanelWindow()
        super.init()
        panel.delegate = self
        panel.onHideRequest = { [weak self] in self?.hideOnRequest() }
        panel.onZoomRequest = { [weak self] in self?.zoomWidth() }

        // Контент: [glass-підкладка] → SwiftUI-hosting → ручка ресайзу.
        // Скло МУСИТЬ бути найнижче (за hosting), щоб blur столу лягав ПІД
        // прозорий SwiftUI-корінь (Glass-тема — DESIGN-DIRECTIONS §1)
        let hover = HoverView()
        let glass = Self.makeGlassBackingView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        hover.addSubview(glass)
        glassBacking = glass

        let hosting = NSHostingView(rootView: PanelRevealEffect(content: rootView))
        // ❗ Вимикаємо window-sizing: за замовчуванням NSHostingView створює
        // констрейнти розміру ВІКНА зі SwiftUI-контенту — панель росла/їхала,
        // коли відкривався expanded-редактор чи сабпанель. Розмір панелі
        // диктує ТІЛЬКИ PanelController (visibleFrame), контент — усередині.
        hosting.sizingOptions = []
        // ❗ Прозора смужка заголовка додає contentView верхній safe area
        // (~32pt): SwiftUI зсунув би весь вміст униз. Вміст іде на повну
        // висоту, а відступ під червону кнопку - у самій шапці
        // (ContentView.header, SPEC §15.78)
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hover.addSubview(hosting)

        let handle = ResizeHandleView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        hover.addSubview(handle)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: hover.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: hover.trailingAnchor),
            glass.topAnchor.constraint(equalTo: hover.topAnchor),
            glass.bottomAnchor.constraint(equalTo: hover.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: hover.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: hover.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: hover.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: hover.bottomAnchor),
            handle.leadingAnchor.constraint(equalTo: hover.leadingAnchor),
            handle.topAnchor.constraint(equalTo: hover.topAnchor),
            handle.bottomAnchor.constraint(equalTo: hover.bottomAnchor),
            // 8, а не 6: смужка невидима, тож ширина — це суто влучність.
            // Заявлені 6pt на практиці ловились погано (P2.3)
            handle.widthAnchor.constraint(equalToConstant: 8),
        ])
        panel.contentView = hover
        hover.onEnter = { [weak self] in self?.cancelScheduledHide() }
        hover.onExit = { [weak self] in self?.scheduleHide() }
        handle.onDragBegan = { [weak self] in self?.beginInteraction() }
        handle.onDragEnded = { [weak self] in self?.endInteraction() }

        makeEdgeTrigger()
        makeShadowWindow()

        // Матеріальність: показ blur + тінь вікна за темою (§15.17)
        applyMaterialTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(materialChanged),
            name: .embarMaterialChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(materialChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil)

        // Перерахувати розміри при зміні екрана/Dock/menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // При зміні Space — пере-ствердити тригер (страховка від «прилипання»
        // вікна до одного простору)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // Файл-пікер (стоп-баг 2026-07-29): діалог робить панель не-key —
        // без цих guard-ів вона auto-hide-илась просто під час вибору фото
        NotificationCenter.default.addObserver(
            forName: .embarFilePickerWillShow, object: nil, queue: .main
        ) { [weak self] _ in
            self?.filePickerOpen = true
            self?.cancelScheduledHide()
        }
        NotificationCenter.default.addObserver(
            forName: .embarFilePickerDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.filePickerOpen = false
            // Клавіатура — назад у панель (вибір закінчено, друк далі)
            self?.panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Розміри (SPEC §1.1)

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let saved = EmbarDefaults.store.double(forKey: Self.widthKey)
        let width: CGFloat
        if saved > 0 {
            width = min(max(saved, Self.resizeMin), Self.resizeMax)
        } else {
            width = min(max(vf.width * 0.25, Self.defaultClampMin), Self.defaultClampMax)
        }
        // Низ — від САМОГО низу екрана (frame, не visibleFrame — інакше на
        // робочому столі панель зупинялась над Dock-ом і висота стрибала),
        // верх — під menu bar; з усіх трьох боків зазор edgeInset —
        // «левітуюча» панель (фідбек 2026-07-19)
        let bottom = screen.frame.minY + Self.edgeInset
        return NSRect(x: vf.maxX - width - Self.edgeInset, y: bottom,
                      width: width, height: vf.maxY - Self.edgeInset - bottom)
    }

    // MARK: - Показ / приховання

    /// Тривалості несиметричні (рішення 2026-08-21): захід повільніший і
    /// багатший (слайд + масштаб вмісту + тінь), вихід швидший і простіший
    /// (лише слайд). Закриття свідомо НЕ дзеркальне відкриттю
    private static let showDuration: TimeInterval = 0.68
    private static let hideDuration: TimeInterval = 0.24
    /// Крива появи: різкий старт і довге сповільнення (сильна децелерація,
    /// без пружин і відскоків) — cubic-bezier(.16, 1, .3, 1)
    private static let showTiming = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// SwiftUI-двійник showTiming — масштаб вмісту йде синхронно зі слайдом
    private static let showAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1, duration: showDuration)
    /// Крива ховання — простіша, як у прототипі: cubic-bezier(.4, 0, .2, 1)
    private static let slideTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    /// Reduce Motion: руху немає, лишається фейд — ОДНАКОВИЙ в обидва
    /// боки (P2.1: закриття було коротшим і читалось як обрив)
    private static let reduceMotionFade: TimeInterval = 0.2

    // Кореневий фікс фокуса (фідбек ×3, 2026-07-07): NSWindow памʼятає
    // first responder назавжди — тому (а) при хованні його стираємо,
    // (б) при кожному показі композер активної поверхні бере фокус через
    // ці нотифікації. Назва блокнота отримує фокус ЛИШЕ по кліку.

    func show(reason: PanelShowReason = .programmatic) {
        cancelScheduledHide()
        // Інвалідувати незавершене ховання: його completion не має orderOut-ити
        // щойно показану панель
        hideGeneration += 1
        isHiding = false
        // ❗ І СПИНИТИ його рух, а не лише знеславити completion: інакше
        // на одну рамку лягали дві зустрічні анімації (ховання тягне
        // вправо, показ — вліво), і поява виходила смиканою або миттєвою
        // (P2.2). Нульова анімація на поточному значенні знімає стару
        stopFrameAnimation()
        guard let screen = NSScreen.main else { return }
        let target = targetFrame(on: screen)
        guard panel.frame != target || !panel.isVisible else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if !panel.isVisible {
            if reduceMotion {
                // Reduce Motion: без руху й масштабу — одразу на місці,
                // зʼявиться простим фейдом
                panel.setFrame(target, display: false)
                panel.alphaValue = 0
            } else {
                // Стартуємо повністю за правим краєм екрана (+зазор, бо панель
                // тепер стоїть на edgeInset лівіше краю)
                panel.setFrame(target.offsetBy(dx: target.width + Self.edgeInset, dy: 0),
                               display: false)
            }
            // Тінь наростає разом з появою (0 → значення теми)
            shadowWindow?.alphaValue = 0
        }
        // orderFrontRegardless: показує на ПОТОЧНОМУ Space (зокрема fullscreen),
        // не активуючи застосунок і не перемикаючи простір.
        // БЕЗ makeKey(): hover не має красти фокус клавіатури з застосунку,
        // де користувач друкує; клік у поле панелі зробить її key сам
        // (becomesKeyOnlyIfNeeded = true)
        panel.orderFrontRegardless()
        // Композер активної поверхні готує фокус — «нуль тертя між думкою
        // і можливістю записати її»
        NotificationCenter.default.post(name: .embarPanelDidShow, object: nil,
                                        userInfo: ["reason": reason.rawValue])
        // Анімуємо на наступному циклі runloop — інакше перший показ
        // може «стрибнути» одразу в кінцеву позицію без слайду
        Task { [weak self] in
            guard let self else { return }
            if reduceMotion {
                // Масштаб вимкнено самим PanelRevealEffect (env reduceMotion);
                // ставимо стан без анімації, щоб вміст був 1.0 одразу
                PanelRevealState.shared.revealed = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Self.reduceMotionFade
                    self.panel.animator().setFrame(target, display: true)
                    self.panel.animator().alphaValue = 1
                    self.shadowWindow?.animator().alphaValue = self.shadowTargetAlpha
                }
                return
            }
            // Страховка після обірваного Reduce Motion-фейду ховання
            self.panel.alphaValue = 1
            // Вміст «доростає» 0.94 → 1.0 синхронно зі слайдом (та сама
            // крива й тривалість). Явний withAnimation, а не .animation(value:),
            // щоб скидання стану при хованні було миттєвим
            withAnimation(Self.showAnimation) {
                PanelRevealState.shared.revealed = true
            }
            let generation = self.hideGeneration
            self.isAnimatingFrame = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.showDuration
                ctx.timingFunction = Self.showTiming
                self.panel.animator().setFrame(target, display: true)
                self.shadowWindow?.animator().alphaValue = self.shadowTargetAlpha
            } completionHandler: { [weak self] in
                guard let self, self.hideGeneration == generation else { return }
                self.isAnimatingFrame = false
            }
        }
    }

    /// Зняти рух, що зараз іде: нульова анімація на поточному значенні
    /// заміщає активну. Без цього зустрічні show/hide накладаються
    private func stopFrameAnimation() {
        guard isAnimatingFrame else { return }
        isAnimatingFrame = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().setFrame(panel.frame, display: false)
            shadowWindow?.animator().alphaValue = shadowWindow?.alphaValue ?? 0
        }
    }

    /// Чи курсор зараз над будь-яким видимим вікном застосунку (popover,
    /// меню, датапікер — це ОКРЕМІ вікна macOS; без цієї перевірки перехід
    /// миші з панелі на острівець-popover тригерив auto-hide)
    private var mouseInsideAppWindow: Bool {
        let loc = NSEvent.mouseLocation
        return NSApp.windows.contains { w in
            // Тінь ігнорує мишу, але її рамка ширша за панель — без цього
            // винятку курсор «над туманом» блокував би auto-hide.
            // Стіки-віджети — самостійні вікна: курсор над ними не має
            // тримати панель відкритою (SPEC §2.7)
            // Вікна онбордингу теж не «тримають» панель: картка знайомства
            // стоїть по центру екрана, і курсор над нею не мусив би
            // блокувати auto-hide
            w.isVisible && w !== edgeTrigger && w !== shadowWindow
                && !(w is DesktopStickyPanel)
                && !(w is OnboardingAuxWindow)
                && w.frame.contains(loc)
        }
    }

    /// Відкритий системний файл-пікер: панель тримається на місці
    private var filePickerOpen = false

    // MARK: - Замок взаємодії (F7)
    //
    // Поки людина тягне край панелі, auto-hide заблоковано ПОВНІСТЮ.
    // Причина конкретна: ширина затиснута [320…480], і тяга за межу
    // відводить курсор за панель — трекінг-область чесно шле mouseExited,
    // панель призначає ховання і їде геть просто з-під руки. Далі хаос:
    // драг ще живий і продовжує setFrame уже на панель, що ховається,
    // а edge-тригер показує її знову.

    private var interactionDepth = 0
    private var isInteracting: Bool { interactionDepth > 0 }

    func beginInteraction() {
        interactionDepth += 1
        cancelScheduledHide()
    }

    func endInteraction() {
        interactionDepth = max(0, interactionDepth - 1)
        guard interactionDepth == 0 else { return }
        // Драг міг закінчитись далеко за панеллю — вирішуємо долю ЗАРАЗ,
        // бо mouseExited за час замка вже пролетів і більше не прийде
        if !mouseInsideAppWindow { scheduleHide() }
    }

    func hide() {
        guard panel.isVisible, !isLocked, !filePickerOpen, !isInteracting else { return }
        // Курсор над popover/меню/панеллю → не ховаємо; перевіримо знову
        // за 550 мс (коли попап закриється і миша піде — панель сховається)
        guard !mouseInsideAppWindow else {
            scheduleHide()
            return
        }
        animateOut()
    }

    /// Глобальний хоткей (Option+E): явний показ/приховання, без guard-ів
    /// hover/lock — це усвідомлена дія користувача.
    /// isVisible лишається true всі 0.24с ховання — «ховається» = «показати»
    func toggle() {
        cancelScheduledHide()
        if panel.isVisible && !isHiding {
            animateOut()
        } else {
            show(reason: .hotkey)
            // Хоткей — усвідомлена дія: панель одразу key, друк без кліку
            // (hover-показ навмисно клавіатуру НЕ краде)
            panel.makeKey()
        }
    }

    // MARK: - Онбординг (Такт 2)

    /// Чи панель зараз на екрані
    var isOnScreen: Bool { panel.isVisible }

    /// Чи ввімкнено lock (панель не ховається сама)
    var isPinned: Bool { isLocked }

    /// Прибрати панель, щоб Такт 2 знайомства міг навчити викликати її
    /// жестом. На відміну від hide() ігнорує lock і положення курсора —
    /// це не auto-hide, а свідома дія сценарію
    /// Чи панель зараз на екрані. Потрібне пейволу: на час системного
    /// діалогу покупки він опускається під панель і мусить знати, чи
    /// повертати її назад (SPEC §15.77ж)
    var isPanelVisible: Bool { panel.isVisible }

    func hideForOnboarding() {
        cancelScheduledHide()
        guard panel.isVisible, !isHiding else { return }
        animateOut()
    }

    private func animateOut() {
        // ❗ Повторний вхід під час уже активного ховання (двічі підряд
        // прилетів mouseExited, або hide() слідом за toggle()) рахував
        // зсув від ПОТОЧНОЇ, уже наполовину виїханої рамки: панель
        // стрибала за екран за решту 0.24с і читалась як «просто зникла»
        // (P2.1)
        guard !isHiding else { return }
        // Стерти памʼять вікна про «останнє поле»: інакше AppKit при
        // наступній активації відновлює редактор назви із select-all
        panel.makeFirstResponder(nil)
        NotificationCenter.default.post(name: .embarPanelDidHide, object: nil)
        isHiding = true
        hideGeneration += 1
        let generation = hideGeneration
        // Показ міг ще їхати — його рух знімаємо, щоб ховання починалось
        // із чистого аркуша (P2.2)
        stopFrameAnimation()
        isAnimatingFrame = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Закриття свідомо простіше за відкриття: швидший слайд без масштабу
        // (масштаб скидається вже за екраном); тінь гасне разом зі слайдом
        NSAnimationContext.runAnimationGroup { ctx in
            if reduceMotion {
                // Та сама тривалість, що у фейді появи (0.2): раніше тут
                // було 0.18 — закриття виходило коротшим за відкриття і
                // читалось як обрив (P2.1). Страховка на alpha: обірваний
                // фейд міг лишити не-одиницю, і тоді «гаснути» вже нема з чого
                panel.alphaValue = 1
                ctx.duration = Self.reduceMotionFade
                panel.animator().alphaValue = 0
            } else {
                ctx.duration = Self.hideDuration
                ctx.timingFunction = Self.slideTiming
                let off = panel.frame.offsetBy(dx: panel.frame.width + Self.edgeInset, dy: 0)
                panel.animator().setFrame(off, display: true)
            }
            shadowWindow?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.isHiding = false
            self.isAnimatingFrame = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            // Панель уже за екраном/невидима — скинути масштаб вмісту до
            // стартових 0.94 миттєво, щоб наступна поява знову росла від краю
            PanelRevealState.shared.revealed = false
        }
    }

    /// Відхід миші з панелі → ховаємо через 550 мс (прототип: scheduleClose)
    private func scheduleHide() {
        guard !filePickerOpen, !isInteracting else { return }
        cancelScheduledHide()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.55))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func cancelScheduledHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    // MARK: - Тінь-«туман» (click-through вікно під панеллю)

    private func makeShadowWindow() {
        // EmbarPanel, не NSPanel: успадковує constrainFrameRect-override —
        // вікно тіні свідомо виходить за межі екрана (запас під розмиття)
        let win = EmbarPanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        win.level = panel.level
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true      // кліки йдуть КРІЗЬ тінь
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        let layer = CALayer()
        // Сам шар нічого не малює — лише розмита тінь по контуру панелі
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 32
        layer.shadowOffset = .zero
        view.layer?.addSublayer(layer)
        win.contentView = view
        shadowLayer = layer
        shadowWindow = win

        // Дочірнє вікно ПІД панеллю: слайд/показ/ховання панелі тягне
        // тінь за собою автоматично
        panel.addChildWindow(win, ordered: .below)
        layoutShadow()
    }

    /// Розмір/контур тіні під поточну рамку панелі (виклик при показі,
    /// ресайзі ручкою і зміні екрана; слайд origin-only — дочірнє вікно
    /// їде саме)
    private func layoutShadow() {
        guard let win = shadowWindow, let layer = shadowLayer else { return }
        let m = Self.shadowMargin
        win.setFrame(panel.frame.insetBy(dx: -m, dy: -m), display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: win.frame.size)
        layer.shadowPath = CGPath(
            roundedRect: CGRect(x: m, y: m, width: panel.frame.width,
                                height: panel.frame.height),
            cornerWidth: 16, cornerHeight: 16, transform: nil)
        CATransaction.commit()
    }

    /// Ширина панелі змінилась (ручка ресайзу, zoom) — тінь наздоганяє живцем
    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        layoutShadow()
    }

    // MARK: - Edge trigger (невидима смужка 4pt на правому краю)

    private func makeEdgeTrigger() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Та сама висота, що в панелі: до самого низу екрана
        let rect = NSRect(x: vf.maxX - 4, y: screen.frame.minY,
                          width: 4, height: vf.maxY - screen.frame.minY)

        // Теж nonactivating NSPanel: звичайний NSWindow звичайного застосунку
        // macOS не показує над fullscreen-просторами
        let trigger = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        trigger.level = .statusBar
        trigger.isOpaque = false
        // Майже невидима, але отримує події миші
        trigger.backgroundColor = NSColor.black.withAlphaComponent(0.02)
        trigger.ignoresMouseEvents = false
        trigger.hidesOnDeactivate = false
        trigger.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        trigger.hasShadow = false

        let hover = HoverView(frame: NSRect(origin: .zero, size: rect.size))
        hover.onEnter = { [weak self] in
            // Settings «Виклик при наведенні»: вимкнено → лише хоткей
            let d = EmbarDefaults.store
            guard d.object(forKey: "edgeHoverEnabled") == nil
                || d.bool(forKey: "edgeHoverEnabled") else { return }
            self?.show(reason: .edgeHover)
        }
        trigger.contentView = hover
        trigger.orderFrontRegardless()
        edgeTrigger = trigger
    }

    // MARK: - NSWindowDelegate

    /// Спільний редактор полів панелі з брендовою кареткою (SPEC §15.54):
    /// текст у TextField-ах набирає field editor вікна, тож каретку
    /// фарбуємо саме тут — на видимих полях це зробити неможливо
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        BrandFieldEditors.editor(for: sender)
    }

    /// Червона кнопка і ⌘W (SPEC §15.78): панель НЕ закривається як
    /// вікно і застосунок не виходить - вона ховається тим самим слайдом,
    /// що при відведенні курсора. Свідома дія, як хоткей: lock не
    /// зупиняє (edge-hover чи ⌥E повернуть панель)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        hideOnRequest()
        return false
    }

    /// Спільний шлях червоної і жовтої кнопок, ⌘W і ⌘M
    func hideOnRequest() {
        cancelScheduledHide()
        if panel.isVisible, !isHiding { animateOut() }
    }

    // MARK: - Зелена кнопка: zoom ширини 320 ↔ 480 (SPEC §15.78є)

    /// Вікно панелі - для тестів (делегатні шляхи кнопок)
    var window: NSWindow { panel }

    /// Чиста геометрія zoom-у: ширина перемикається між мінімумом і
    /// максимумом ресайзу (від 400 і ширше - до 320, вужче - до 480),
    /// правий край і висота без змін. Завжди повертає ІНШУ ширину, тож
    /// вбудована логіка AppKit «рамка = стандартна → повернути збережену»
    /// ніколи не спрацьовує - кожен клік перемикає
    static func zoomedFrame(current: NSRect) -> NSRect {
        let width = current.width >= (resizeMin + resizeMax) / 2 ? resizeMin : resizeMax
        return NSRect(x: current.maxX - width, y: current.minY,
                      width: width, height: current.height)
    }

    /// Зелена кнопка: перемкнути ширину (короткий слайд лівого краю, як
    /// у прототипу ховання) і зберегти її так само, як після ручки.
    /// Не під час показу/ховання - рамка тоді належить анімації (P2.1)
    func zoomWidth() {
        guard panel.isVisible, !isAnimatingFrame, !isHiding else { return }
        let target = Self.zoomedFrame(current: panel.frame)
        EmbarDefaults.store.set(Double(target.width), forKey: Self.widthKey)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = Self.slideTiming
            panel.animator().setFrame(target, display: true)
        }
    }

    /// .resizable потрібен для зеленої кнопки, але вмикає й нативне
    /// тягання країв. Політика (чиста, під тестом): лівий край - той самий
    /// ресайз, що робить наша ручка (ширина 320…480, висота і правий край
    /// на місці; AppKit сам тримає maxX при драгу за лівий край) - тож
    /// якщо системна зона на краю перехопить драг раніше за
    /// ResizeHandleView, результат однаковий; верх/низ/правий край -
    /// відхиляємо. setFrame ручки і zoomWidth сюди не заходять
    static func nativeResizeSize(proposed: NSSize, current: NSRect,
                                 mouseX: CGFloat) -> NSSize {
        guard mouseX < current.midX else { return current.size }
        let width = min(max(proposed.width, resizeMin), resizeMax)
        return NSSize(width: width, height: current.height)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel else { return frameSize }
        return Self.nativeResizeSize(proposed: frameSize, current: panel.frame,
                                     mouseX: NSEvent.mouseLocation.x)
    }

    /// Нативний драг за край - той самий замок auto-hide, що в ручки (F7),
    /// і те саме збереження ширини наприкінці
    func windowWillStartLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        beginInteraction()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        EmbarDefaults.store.set(Double(panel.frame.width), forKey: Self.widthKey)
        endInteraction()
    }

    /// Панель втратила фокус → auto-hide (якщо не locked).
    /// НЕ ховаємо, якщо курсор ще над панеллю: над fullscreen-застосунком
    /// nonactivating-панель може втратити key одразу після показу —
    /// без цієї перевірки вона б зникала миттєво. Догляне mouse-exit (hover).
    func windowDidResignKey(_ notification: Notification) {
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
        scheduleHide()
    }

    // MARK: - Зміни екрана / Space

    @objc private func screenParamsChanged() {
        guard let screen = NSScreen.main else { return }
        // Пересунути тригер-смужку
        if let trigger = edgeTrigger {
            let vf = screen.visibleFrame
            trigger.setFrame(NSRect(x: vf.maxX - 4, y: screen.frame.minY,
                                    width: 4, height: vf.maxY - screen.frame.minY),
                             display: false)
        }
        // І панель, якщо відкрита. ❗ Але НЕ під час руху: цей setFrame
        // не анімований, і потрапляючи в середину слайду він телепортував
        // панель на місце, після чого completion ховання просто робив
        // orderOut — рівно «закрилась різко, без анімації» (P2.1).
        // Нотифікація прилітає частіше, ніж здається: Dock, зміна
        // роздільності, підключення дисплея, вихід зі сну
        if panel.isVisible, !isAnimatingFrame {
            panel.setFrame(targetFrame(on: screen), display: true)
        }
    }

    @objc private func activeSpaceChanged() {
        edgeTrigger?.orderFrontRegardless()
    }
}
