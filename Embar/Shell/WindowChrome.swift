//
//  WindowChrome.swift
//  Embar
//
//  Утилітарна смужка заголовка (App Review, Guideline 4, 2026-09-25).
//
//  Рецензент відхилив білд 3: «the app presents a window that does not
//  contain the necessary title bar buttons» - на знімку наша бічна
//  панель. Рішення: усі вікна, що живуть без системної рамки (панель,
//  пейвол, знайомство, стіки-віджети), отримують патерн утилітарної
//  панелі macOS - як «Шрифти» чи «Кольори»: ЛИШЕ червона кнопка
//  закриття, без згортання і розгортання. Смужка прозора, назва
//  прихована, вміст на повну висоту - вигляд той самий, плюс одна
//  червона крапка зліва вгорі.
//
//  ❗ Заголовкова маска НЕ заважає показу над fullscreen-просторами:
//  для nonactivating NSPanel із .fullScreenAuxiliary це той самий
//  рецепт, що в «плаваючих» панелях (titled + fullSizeContentView).
//  Старе застереження в шапці PanelController стосувалось звичайного
//  NSWindow, не NSPanel.
//
//  Кожен виклик - одне місце правди: якщо Apple колись вимагатиме інший
//  набір кнопок, змінюємо тут.
//

import AppKit
import SwiftUI

enum WindowChrome {
    /// Маска, з якою створюється вікно утилітарного патерну (лише червона
    /// кнопка): без .miniaturizable і без .resizable. Панель додає обидва
    /// біти сама - у неї три кнопки (SPEC §15.78є)
    static let utilityMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]

    /// Які системні кнопки лишаються видимими
    enum Buttons {
        /// Лише червона (пейвол, знайомство)
        case closeOnly
        /// Червона, жовта, зелена (панель): жовта = сховати, зелена = zoom
        /// ширини - вимагає .miniaturizable і .resizable у масці
        case all
    }

    /// Діаметр системної кнопки закриття (macOS 26: 14pt)
    static let closeButtonDiameter: CGFloat = 14
    /// Крок між центрами трьох кнопок (macOS: 20pt)
    static let buttonPitch: CGFloat = 20
    /// Висота смужки заголовка, що перехоплює кліки (виміряно: safe area
    /// 32, стандартний рядок кнопок 28). У верстці вище цієї межі нічого
    /// клікабельного не кладемо
    static let titlebarHeight: CGFloat = 28

    /// ЄДИНЕ правило положення кнопки для всіх вікон (ревізія
    /// 2026-09-27, друга ітерація за знімками): центр кнопки = ЦЕНТР ДУГИ
    /// кута, тобто (r, r) від рогу. Тоді просвіт від кнопки до верхнього
    /// краю, до лівого краю і до самої кривої однаковий (r − 7). Для
    /// панелі (r = 16) це рівно стандартне місце macOS (просвіт 9, як у
    /// Terminal); для пейволу і знайомства (r = 32) - глибше, там, де
    /// стояв старий хрестик пейволу. Попередня «дотична» версія (14 / 10)
    /// читалась як «на самому куті» і на r = 32 вилазила за заокруглення
    static func closeButtonInset(cornerRadius r: CGFloat) -> CGFloat {
        r.rounded()
    }

    /// Поставити кнопку на місце за правилом вище і ТРИМАТИ її там:
    /// AppKit перекладає кнопку при кожному перетилінгу смужки (resize,
    /// key/inactive, appearance), тож слухаємо зміну її рамки і
    /// повертаємо. Обʼєкт-пін живе стільки, скільки вікно.
    ///
    /// ❗ Викликати ПІСЛЯ `window.contentView = …`: коли ціль не вміщається
    /// у смужку (r > 25), кнопка переїжджає в contentView (див.
    /// CloseButtonPin), і заміна contentView після цього її б загубила
    static func pinCloseButton(in window: NSWindow, cornerRadius: CGFloat) {
        let pin = CloseButtonPin(window: window,
                                 inset: closeButtonInset(cornerRadius: cornerRadius))
        objc_setAssociatedObject(window, &pinKey, pin, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var pinKey = 0

    /// Зробити з titled-вікна утилітарну панель: прозора смужка, назва
    /// прихована (лишається для VoiceOver), кнопки згортання/розгортання
    /// сховані, роздільник під смужкою вимкнений.
    ///
    /// Викликати ПІСЛЯ створення вікна з `utilityMask` у styleMask -
    /// і ПЕРЕД властивостями рівня/поведінки (зміна маски може їх
    /// скинути; порядок у контролерах саме такий, тест
    /// `WindowChromeTests` тримає інваріант)
    static func applyUtilityTitlebar(to window: NSWindow, title: String,
                                     buttons: Buttons = .closeOnly) {
        window.styleMask.formUnion(utilityMask)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Без лінії під смужкою: у Reduce Transparency і темній темі вона
        // проявлялась би як окрема сіра полоса
        window.titlebarSeparatorStyle = .none
        let hideExtra = buttons == .closeOnly
        window.standardWindowButton(.miniaturizeButton)?.isHidden = hideExtra
        window.standardWindowButton(.zoomButton)?.isHidden = hideExtra
        // Утилітарні вікна не потрапляють у меню «Вікно» і ⌘` цикл
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior.insert(.ignoresCycle)
    }

    /// Контейнер для SwiftUI-хостингу в titled-вікні.
    ///
    /// ❗ NSHostingView з фіксованою рамкою вмісту (640×720) звітує
    /// intrinsicContentSize, і Auto Layout рамки вікна складає «смужка
    /// (32) + вміст (720)» - вікно росло до 752, а вміст сідав донизу,
    /// лишаючи вгорі прозору смугу з кнопкою поза карткою (знімок
    /// 2026-09-25). Плоский NSView без власного розміру, до країв якого
    /// пришпилений хостинг, цю арифметику не запускає - той самий
    /// прийом, що в панелі (HoverView) і віджетах
    static func fullHeightContainer(for hosting: NSView) -> NSView {
        let container = NSView()
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Рамка червоної кнопки в координатах contentView (origin знизу
    /// зліва) - для тестів і зондів
    static func closeButtonFrame(in window: NSWindow) -> NSRect? {
        guard let button = window.standardWindowButton(.closeButton),
              let content = window.contentView else { return nil }
        return button.convert(button.bounds, to: content)
    }
}

/// Тримає системну кнопку закриття в потрібній точці (див.
/// `WindowChrome.pinCloseButton`).
///
/// Два режими, доведені зондами 2026-09-27:
/// · **у смужці** (ціль вміщається в її 32pt - панель, r = 16): лише
///   повертаємо рамку після кожного перетилінгу;
/// · **у contentView** (r = 32: центр на 32 - нижня половина кнопки
///   опинялась за межами NSTitlebarContainerView і НЕ клікалась,
///   `hitTest` повертав наш вміст): кнопка переїжджає в contentView,
///   де хіт-тест і малювання працюють, а клік, як і раніше, іде
///   в `performClose` → делегат. ⚠️ Гліф ✕ при наведенні в цьому режимі
///   НЕ зʼявляється: його вмикає NSTitlebarContainerView за рухом
///   курсора В МЕЖАХ смужки, звіряючи з кешованим прямокутником
///   стандартного місця кнопок (доведено знімками зі справжнім курсором
///   2026-09-27: гліф світився на старому місці, на кнопці - ні). Ми
///   лише прибираємо застарілу область рамки (NSThemeFrame), щоб гліф
///   не зʼявлявся «збоку вище», і ставимо власну на рамці кнопки -
///   вона тримає хіт-тест чистим, але гліфа не дає. Публічного API
///   пересунути кластер кнопок немає; рішення - SPEC §15.78е(2)
final class CloseButtonPin: NSObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    private weak var window: NSWindow?
    private let inset: CGFloat
    private var observers: [NSObjectProtocol] = []
    private var applying = false
    /// Область наведення, яку поставили ми (режим contentView)
    private var rolloverArea: NSTrackingArea?
    /// Опції області рамки, яку замінюємо (скопійовані з оригіналу)
    private var rolloverOptions: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]

    /// Чи кнопка живе в contentView (ціль не вміщається у смужку)
    private(set) var hostsInContent = false

    init(window: NSWindow, inset: CGFloat) {
        self.window = window
        self.inset = inset
        super.init()
        guard let button = window.standardWindowButton(.closeButton),
              let titlebar = button.superview else { return }
        hostsInContent = inset + button.frame.height / 2 > titlebar.bounds.height
        if let stale = themeFrameAreas(of: window).first {
            rolloverOptions = stale.options
        }
        button.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSView.frameDidChangeNotification, object: button,
            queue: .main) { [weak self] _ in self?.apply() })
        observers.append(center.addObserver(
            forName: NSWindow.didResizeNotification, object: window,
            queue: .main) { [weak self] _ in self?.apply() })
        apply()
    }

    /// Області відстеження, що належать рамці вікна (не наші і не
    /// віджетів) - саме вони вмикають гліф ✕ при наведенні
    private func themeFrameAreas(of window: NSWindow) -> [NSTrackingArea] {
        guard let frame = window.contentView?.superview else { return [] }
        return frame.trackingAreas.filter { $0.owner === frame && $0 !== rolloverArea }
    }

    /// Ціль у координатах contentView (верхній лівий кут = inset, inset),
    /// переведена в координати батька кнопки - хай він і flipped
    func apply() {
        guard !applying, let window, let content = window.contentView,
              let button = window.standardWindowButton(.closeButton) else { return }
        applying = true
        defer { applying = false }

        if hostsInContent, button.superview !== content {
            // Переїзд (або повторний після заміни contentView) - поверх
            // усього вмісту, щоб хостинг SwiftUI не перекривав кнопку
            content.addSubview(button, positioned: .above, relativeTo: nil)
        }
        guard let parent = button.superview else { return }
        let size = button.frame.size
        let target = NSRect(x: inset - size.width / 2,
                            y: content.bounds.height - inset - size.height / 2,
                            width: size.width, height: size.height)
        let inParent = content.convert(target, to: parent)
        if button.frame != inParent { button.frame = inParent }

        guard hostsInContent, let frame = content.superview else { return }
        // Область наведення: чужі (застарілі, з координатами смужки) геть,
        // наша - на рамці кнопки; власник той самий NSThemeFrame, бо
        // саме його mouseEntered/mouseExited перемикає гліф
        for stale in themeFrameAreas(of: window) { frame.removeTrackingArea(stale) }
        let wanted = content.convert(target, to: frame)
        if let area = rolloverArea, area.rect == wanted,
           frame.trackingAreas.contains(where: { $0 === area }) { return }
        if let area = rolloverArea { frame.removeTrackingArea(area) }
        let area = NSTrackingArea(rect: wanted, options: rolloverOptions,
                                  owner: frame, userInfo: nil)
        frame.addTrackingArea(area)
        rolloverArea = area
    }
}

/// Мʼяке світле сяйво під кнопкою там, де під нею зображення (ревізія
/// 2026-09-27): коло діаметром 3 кнопки, білий 35% у центрі → 0 по краю,
/// без чіткої межі. Класти overlay-ем `.topLeading` на шар із фото; на
/// кремовому тлі панелі його немає. Reduce Transparency не чіпає - це
/// градієнт у вмісті, не прозорість вікна
struct CloseButtonGlow: View {
    let cornerRadius: CGFloat
    /// Скільки кнопок накрити: 1 (пейвол, знайомство) або 3 (панель)
    var buttons: Int = 1

    var body: some View {
        let inset = WindowChrome.closeButtonInset(cornerRadius: cornerRadius)
        let diameter = WindowChrome.closeButtonDiameter * 3
        let span = CGFloat(buttons - 1) * WindowChrome.buttonPitch
        Group {
            if buttons <= 1 {
                RadialGradient(colors: [.white.opacity(0.35), .white.opacity(0)],
                               center: .center, startRadius: 0, endRadius: diameter / 2)
                    .frame(width: diameter, height: diameter)
            } else {
                // Три кнопки - витягнуте сяйво тієї самої мʼякості: капсула
                // 35% білого, розмита до нуля по краю, без чіткої межі
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: span + diameter * 0.6, height: diameter * 0.6)
                    .blur(radius: diameter * 0.2)
                    .frame(width: span + diameter, height: diameter)
            }
        }
        .offset(x: inset - diameter / 2, y: inset - diameter / 2)
        .allowsHitTesting(false)
    }
}
