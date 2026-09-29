#if DEBUG
//
//  PerfProbe.swift
//  Embar
//
//  ⚠️ Вимірювальний зонд пісочниці (`-EmbarTestSandbox -SandboxPerfProbe`).
//  Поза пісочницею НЕ активується ніколи; у звичайному запуску вся ціна —
//  одна перевірка Bool.
//
//  Що міряє:
//  · зависання головного потоку (пінг із фонового потоку кожні 30 мс);
//  · вартість і кількість перерахунків розкладки стіни (LazyTwoColumnMasonry)
//    та фільтрації стіків (хук record із гарячого коду);
//  · автоматичний сценарій без Accessibility: скрол стіни (керуємо
//    NSScrollView зсередини процесу), перемикання фільтрів, синтетичний
//    друк (NSEvent keyDown у власне key-вікно).
//
//  Підсумок пише в лог рядками «PERF:» — їх зручно grep-ати зі stderr.
//

import AppKit
import SwiftUI

final class PerfProbe: @unchecked Sendable {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let isActive =
        SandboxEnvironment.isActive && LaunchArgs.flag("SandboxPerfProbe")

    static let shared = PerfProbe()
    private init() {}

    // MARK: - Лічильники гарячих місць (потокобезпечно через lock)

    private let lock = NSLock()
    private var counters: [String: (count: Int, totalMS: Double, maxMS: Double)] = [:]

    /// Викликається з гарячого коду (розкладка/фільтр): накопичити тривалість
    func record(_ name: String, seconds: TimeInterval) {
        guard Self.isActive else { return }
        let ms = seconds * 1000
        lock.lock()
        var entry = counters[name] ?? (0, 0, 0)
        entry.count += 1
        entry.totalMS += ms
        entry.maxMS = max(entry.maxMS, ms)
        counters[name] = entry
        lock.unlock()
    }

    /// Зняти й обнулити лічильники (межа між фазами сценарію)
    private func drainCounters() -> String {
        lock.lock()
        let snapshot = counters
        counters = [:]
        lock.unlock()
        guard !snapshot.isEmpty else { return "  (лічильники порожні)" }
        return snapshot.sorted { $0.key < $1.key }.map { name, e in
            String(format: "  %@: %d× · разом %.0f мс · макс %.1f мс",
                   name, e.count, e.totalMS, e.maxMS)
        }.joined(separator: "\n")
    }

    // MARK: - Детектор зависань головного потоку

    private var hangMonitorRunning = false
    private var hangCount = 0       // >50 мс
    private var worstHangMS: Double = 0
    private var hangTotalMS: Double = 0

    private func startHangMonitor() {
        lock.lock(); hangMonitorRunning = true; lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let running = hangMonitorRunning
                lock.unlock()
                guard running else { return }
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async { [self] in
                    let delayMS = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                    guard delayMS > 50 else { return }
                    lock.lock()
                    hangCount += 1
                    hangTotalMS += delayMS
                    worstHangMS = max(worstHangMS, delayMS)
                    lock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
    }

    private func stopHangMonitor() {
        lock.lock(); hangMonitorRunning = false; lock.unlock()
    }

    private func drainHangs() -> String {
        lock.lock()
        let line = String(format: "  зависань >50мс: %d · найгірше %.0f мс · разом %.0f мс",
                          hangCount, worstHangMS, hangTotalMS)
        hangCount = 0; worstHangMS = 0; hangTotalMS = 0
        lock.unlock()
        return line
    }

    // MARK: - Доступ до живих обʼєктів (реєструє ContentView)

    @MainActor private weak var stickies: StickiesModel?
    /// Перемкнути таб панелі: "stickies" | "notes" | "reader"
    @MainActor private var switchTab: ((String) -> Void)?
    /// Відкрити стрес-блокнот рідера; false — не знайдено
    @MainActor private var openStressBook: (() -> Bool)?
    /// Видимий стік з верхівки стіни - для фази дій (F5)
    @MainActor private var sampleSticker: (() -> Sticker?)?

    @MainActor static func register(stickies: StickiesModel,
                                    switchTab: @escaping (String) -> Void,
                                    openStressBook: @escaping () -> Bool,
                                    sampleSticker: @escaping () -> Sticker?) {
        guard isActive else { return }
        shared.stickies = stickies
        shared.switchTab = switchTab
        shared.openStressBook = openStressBook
        shared.sampleSticker = sampleSticker
    }

    // MARK: - Сценарій

    /// Запустити сценарій через кілька секунд після старту (панель уже
    /// показана і перший рендер завершено)
    @MainActor static func runIfRequested() {
        guard isActive else { return }
        NSLog("PERF: зонд активний — сценарій стартує за 4 с")
        shared.startHangMonitor()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            await shared.runScenario()
            shared.stopHangMonitor()
            NSLog("PERF: сценарій завершено")
        }
    }

    @MainActor private func runScenario() async {
        NSLog("PERF: === фаза 0 · перший рендер (усе від старту досі) ===\n%@\n%@",
              drainCounters(), drainHangs())

        guard let scroll = findWallScrollView() else {
            NSLog("PERF: ‼️ не знайшов NSScrollView стіни — сценарій зупинено")
            return
        }

        await scrollPhase(scroll)
        NSLog("PERF: === фаза 1 · скрол стіни ===\n%@\n%@",
              drainCounters(), drainHangs())

        await filterPhase()
        NSLog("PERF: === фаза 2 · перемикання фільтрів ===\n%@\n%@",
              drainCounters(), drainHangs())

        await actionsPhase()

        await typingPhase()
        NSLog("PERF: === фаза 3 · друк у полі (30 символів) ===\n%@\n%@",
              drainCounters(), drainHangs())

        // Нотатки й рідер — ті самі перевірки на тих самих обсягах
        if let switchTab {
            switchTab("notes")
            try? await Task.sleep(for: .seconds(1))
            NSLog("PERF: === фаза 4а · перший рендер нотаток ===\n%@\n%@",
                  drainCounters(), drainHangs())
            if let scroll = findWallScrollView() {
                await scrollPhase(scroll)
                NSLog("PERF: === фаза 4б · скрол нотаток ===\n%@\n%@",
                      drainCounters(), drainHangs())
            }
            await typingPhase()
            NSLog("PERF: === фаза 4в · друк у полі нотаток ===\n%@\n%@",
                  drainCounters(), drainHangs())
        }
        if let switchTab, let openStressBook {
            switchTab("reader")
            try? await Task.sleep(for: .milliseconds(800))
            if openStressBook() {
                try? await Task.sleep(for: .seconds(1))
                NSLog("PERF: === фаза 5а · відкриття стрес-блокнота ===\n%@\n%@",
                      drainCounters(), drainHangs())
                if let scroll = findWallScrollView() {
                    await scrollPhase(scroll)
                    NSLog("PERF: === фаза 5б · скрол стрічки рідера ===\n%@\n%@",
                          drainCounters(), drainHangs())
                }
            } else {
                NSLog("PERF: ‼️ стрес-блокнот не знайдено — фазу рідера пропущено")
            }
            switchTab("stickies")
        }
    }

    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    // MARK: Фаза 1 — скрол

    @MainActor private func scrollPhase(_ scroll: NSScrollView) async {
        let doc = scroll.documentView
        let maxY = max((doc?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)
        NSLog("PERF: висота документа стіни: %.0f pt", doc?.frame.height ?? 0)
        let steps = 180
        let clock = ContinuousClock()
        var frameTimes: [Double] = []
        for i in 0...steps {
            // Вниз і назад: 0→max→0
            let t = Double(i) / Double(steps)
            let phase = t < 0.5 ? t * 2 : (1 - t) * 2
            let y = maxY * phase
            let start = clock.now
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            // Дочекатися такту головного циклу — сюди входить layout
            await Task.yield()
            frameTimes.append(Self.ms(start.duration(to: clock.now)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        let slow = frameTimes.filter { $0 > 33 }.count
        NSLog("PERF:   кроків скролу: %d · кроків довше 33 мс: %d · найдовший %.0f мс",
              frameTimes.count, slow, frameTimes.max() ?? 0)
    }

    // MARK: Фаза 2 — фільтри

    @MainActor private func filterPhase() async {
        guard let model = stickies else {
            NSLog("PERF: ‼️ StickiesModel не зареєстровано")
            return
        }
        let clock = ContinuousClock()
        for kind in [StickyFilterKind.done, .today, .deadline, .all, .done, .all] {
            let start = clock.now
            model.filterKind = kind
            // Один прохід runloop = рендер нового зрізу
            await Task.yield()
            let elapsed = Self.ms(start.duration(to: clock.now))
            NSLog("PERF:   фільтр → %@: %.0f мс до відпускання потоку",
                  kind.rawValue, elapsed)
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    // MARK: Фаза 2б — дії з ОДНИМ стіком (F5: емоджі / виконано / пін)

    /// Скільки коштує зміна одного обʼєкта серед тисяч: міряємо перший
    /// такт (body + розкладка до відпускання потоку) і хвіст (анімації,
    /// пересортування), плюс лічильники sections/split - видно, СКІЛЬКИ
    /// разів перерахувався весь список через одну картку
    @MainActor private func actionsPhase() async {
        guard let sticker = sampleSticker?() else {
            NSLog("PERF: ‼️ фаза дій: не знайшов живого стіка")
            return
        }
        let clock = ContinuousClock()
        func act(_ name: String, _ body: () -> Void) async {
            _ = drainCounters() // обнулити перед дією
            _ = drainHangs()
            let start = clock.now
            body()
            await Task.yield() // перший такт головного циклу після мутації
            let firstMS = Self.ms(start.duration(to: clock.now))
            // Дати дограти анімаціям/пересортуванню - їхня ціна теж дії
            try? await Task.sleep(for: .milliseconds(800))
            NSLog("PERF:   дія «%@»: перший такт %.0f мс\n%@\n%@",
                  name, firstMS, drainCounters(), drainHangs())
        }
        // Пост — як робить UI (StickyExpandedView): зонд міряє той самий шлях
        await act("емоджі поставити") {
            sticker.emojiTag = "🔥"
            StickerMutation.changed(sticker)
        }
        await act("емоджі зняти") {
            sticker.emojiTag = nil
            StickerMutation.changed(sticker)
        }
        await act("виконано ✓") { StickerService.toggleDone(sticker) }
        await act("виконано назад") { StickerService.toggleDone(sticker) }
        // Ціна ОДНОГО натиску в розгорнутому стіку до чернеток (F5.3):
        // TextEditor писав прямо в @Model, тобто платив рівно це на
        // КОЖНУ літеру. Тепер такої мутації при друці немає взагалі —
        // чернетка їде в базу раз на паузу (0.7 с)
        await act("мутація тексту (ціна літери до F5.3)") {
            sticker.text += "."
        }
        await act("мутація тексту назад") {
            sticker.text = String(sticker.text.dropLast())
        }
        await act("пін") { StickerService.togglePin(sticker) }
        await act("пін назад") { StickerService.togglePin(sticker) }
        NSLog("PERF: === фаза 2б · дії з одним стіком завершено ===")
    }

    // MARK: Фаза 3 — друк

    @MainActor private func typingPhase() async {
        guard let panel = NSApp.windows.first(where: { $0 is EmbarPanel }) else {
            NSLog("PERF: ‼️ панель не знайдено")
            return
        }
        panel.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let text = "перевірка швидкости друку на стіні п"
        let clock = ContinuousClock()
        var worst: Double = 0
        for ch in text.prefix(30) {
            let start = clock.now
            postKeystroke(String(ch), to: panel)
            await Task.yield()
            worst = max(worst, Self.ms(start.duration(to: clock.now)))
            try? await Task.sleep(for: .milliseconds(60))
        }
        NSLog("PERF:   найдовший такт друку: %.0f мс", worst)
    }

    /// Синтетичний keyDown/keyUp у ВЛАСНЕ вікно — жодного Accessibility,
    /// подія йде через стандартний sendEvent
    @MainActor private func postKeystroke(_ char: String, to window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: char, charactersIgnoringModifiers: char,
                isARepeat: false, keyCode: 0) else { continue }
            window.sendEvent(event)
        }
    }

    // MARK: Пошук NSScrollView стіни

    /// Найбільший (за площею) NSScrollView панелі, чий документ вищий за
    /// в'юпорт — це стіна
    @MainActor private func findWallScrollView() -> NSScrollView? {
        guard let panel = NSApp.windows.first(where: { $0 is EmbarPanel }),
              let root = panel.contentView else { return nil }
        var best: NSScrollView?
        var bestArea: CGFloat = 0
        func walk(_ view: NSView) {
            if let sv = view as? NSScrollView {
                let area = sv.frame.width * sv.frame.height
                if area > bestArea,
                   (sv.documentView?.frame.height ?? 0) > sv.frame.height {
                    best = sv; bestArea = area
                }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return best
    }
}

#endif
