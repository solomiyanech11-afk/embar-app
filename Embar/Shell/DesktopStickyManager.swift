//
//  DesktopStickyManager.swift
//  Embar
//
//  Менеджер стіків-віджетів на робочому столі (SPEC §2.7): володіє вікнами,
//  тримає інваріант «вікно існує ⇔ isFloating && deletedAt == nil &&
//  !archived», ліміт 10, відновлює віджети після перезапуску і повертає
//  їх на видимий екран після зміни моніторів.
//

import AppKit
import SwiftData

@MainActor
final class DesktopStickyManager {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = DesktopStickyManager()
    /// Максимум віджетів одночасно (SPEC §2.7); 11-й — тост у викликача
    static let maxWidgets = 10

    private var controllers: [UUID: DesktopStickyController] = [:]
    /// Дебаунс clamp-у: didChangeScreenParameters стріляє пачками
    private var clampTask: Task<Void, Never>?

    /// Стік, який ЗАРАЗ їде за курсором (драг із панелі на стіл), і
    /// монітори «відпустили мишу» — страховка на випадок, коли жест
    /// помер у польоті (див. beginDragDetach)
    private weak var draggingSticker: Sticker?
    private var dragMonitors: [Any] = []

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleClamp() }
        }
        // Опівнічний автоархів (AppMaintenance при переході доби) має
        // закрити віджети заархівованих стіків
        NotificationCenter.default.addObserver(
            forName: .embarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileAll() }
        }
    }

    // MARK: - Відновлення після перезапуску

    /// Викликається при старті ПІСЛЯ AppMaintenance.run: стік, що вигрузився
    /// (purge/автоархів), вікна вже не отримає
    func restoreAtLaunch(context: ModelContext) {
        for sticker in floatingStickers(in: context) {
            reconcile(sticker)
        }
        scheduleClamp() // збережена позиція могла лишитись на зниклому моніторі
    }

    private func floatingStickers(in context: ModelContext) -> [Sticker] {
        let descriptor = FetchDescriptor<Sticker>(
            predicate: #Predicate { $0.isFloating == true })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Пере-звірити всі плаваючі стіки з інваріантом (перехід доби)
    private func reconcileAll() {
        let context = EmbarApp.sharedModelContainer.mainContext
        for sticker in floatingStickers(in: context) {
            reconcile(sticker)
        }
    }

    /// Вихід із застосунку: дотиснути незбережені позиції всіх віджетів
    /// (дебаунс міг не встигнути — code review 2026-07-30)
    func flushPendingSaves() {
        controllers.values.forEach { $0.flushPendingSave() }
    }

    // MARK: - Drag з панелі на стіл (SPEC §2.7: зажав картку → потягнув
    // за межі панелі → віджет зʼявляється під курсором і їде за ним)

    /// Область панелі (включно з вікном-тінню) — зона «скасувати драг».
    /// Обидва вікна класу EmbarPanel; віджети виключені за своїм класом
    private var panelArea: NSRect? {
        NSApp.windows
            .filter {
                $0.isVisible && !($0 is DesktopStickyPanel)
                    && String(describing: type(of: $0)) == "EmbarPanel"
            }
            .map(\.frame)
            .reduce(nil) { acc, frame in acc.map { $0.union(frame) } ?? frame }
    }

    func isOverPanel(_ screenPoint: NSPoint) -> Bool {
        panelArea?.contains(screenPoint) ?? false
    }

    /// Почати драг-відкріплення: віджет під курсором. false — ліміт 10.
    /// Якщо віджет уже існує — драг просто перетягує ЙОГО (той самий обʼєкт)
    @discardableResult
    func beginDragDetach(_ sticker: Sticker, at screenPoint: NSPoint) -> Bool {
        guard detach(sticker) else { return false }
        beginDragSession(sticker)
        controllers[sticker.id]?.followDrag(at: screenPoint)
        return true
    }

    func updateDragDetach(_ sticker: Sticker, at screenPoint: NSPoint) {
        controllers[sticker.id]?.followDrag(at: screenPoint)
    }

    /// Кінець драгу: відпустили над панеллю — скасувати (віджет зникає,
    /// стік як був); над столом — зафіксувати позицію одразу.
    /// Ідемпотентний: хто прийшов другим (жест чи страховка) — no-op
    func endDragDetach(_ sticker: Sticker, at screenPoint: NSPoint) {
        guard draggingSticker?.id == sticker.id else { return }
        endDragSession()
        if isOverPanel(screenPoint) {
            reattach(sticker)
        } else {
            controllers[sticker.id]?.flushPendingSave()
        }
    }

    // MARK: - Страховка на обрив драгу (ревʼю 2026-08-18, знахідка 10)
    //
    // Жест живе у @State картки, а картка в лінивій масонрі перестворюється,
    // щойно перескочить колонку. Власні мутації драгу перепакування не
    // викликають, але СТОРОННЯ мутація може (підмітання автоархіву на
    // зміну доби чи після пробудження зі сну) — і тоді .onEnded не
    // приходить узагалі: віджет застигає під курсором, позиція не
    // зберігається, стік лишається isFloating, а відпускання над панеллю
    // більше нічого не скасовує.
    //
    // Тому кінець драгу слухаємо ще й прямо з подій миші: що б не сталося
    // з карткою, «відпустили кнопку» приходить завжди. Локальний монітор
    // ловить події нашого застосунку (панель, віджети), глобальний —
    // відпускання над чужими вікнами; дозволів для миші не треба.

    private func beginDragSession(_ sticker: Sticker) {
        endDragSession()
        draggingSticker = sticker
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            guard let dragged = self.draggingSticker else {
                // Стік зник (видалення під час драгу) — просто прибираємо
                // за собою монітори
                self.endDragSession()
                return
            }
            self.endDragDetach(dragged, at: NSEvent.mouseLocation)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp],
                                                        handler: { event in
            MainActor.assumeIsolated { finish() }
            return event
        }) {
            dragMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp],
                                                          handler: { _ in
            MainActor.assumeIsolated { finish() }
        }) {
            dragMonitors.append(global)
        }
    }

    private func endDragSession() {
        draggingSticker = nil
        dragMonitors.forEach { NSEvent.removeMonitor($0) }
        dragMonitors.removeAll()
    }

    // MARK: - Clamp при зміні екранів

    private func scheduleClamp() {
        clampTask?.cancel()
        clampTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            self?.controllers.values.forEach { $0.clampToVisibleScreens() }
        }
    }

    /// Відкріпити стік на стіл. false — ліміт вичерпано (тост показує
    /// викликач: детач можливий лише з панелі, де тости під рукою)
    @discardableResult
    func detach(_ sticker: Sticker) -> Bool {
        guard controllers[sticker.id] == nil else { return true }
        guard controllers.count < Self.maxWidgets else { return false }
        sticker.isFloating = true
        // Свіже відкріплення = чистий АВТО-розмір під текст: залишкові
        // ручні floatW/floatH (зокрема сміття з ранніх сесій) робили
        // «вузький текст + порожнечу знизу» (фідбек 2026-07-30).
        // Розміри живуть через перезапуск (restore йде reconcile-ом,
        // не detach-ем) — скидаються лише при НОВОМУ витягуванні
        sticker.floatW = nil
        sticker.floatH = nil
        // Глобальні дефолти стилю/розміру — ЛИШЕ при найпершому
        // відкріпленні (floatX ще порожній). Повторний детач раніше
        // затирав особисті налаштування віджета дефолтами — виглядало як
        // «всі віджети стали одного стилю» (баг 2026-07-30)
        if sticker.floatX == nil {
            let defaults = EmbarDefaults.store
            if let style = defaults.string(forKey: "desktopStickyDefaultStyle") {
                sticker.floatStyle = style
            }
            if let size = defaults.string(forKey: "desktopStickyDefaultSize") {
                sticker.floatTextSize = size
            }
        }
        sticker.updatedAt = .now
        reconcile(sticker)
        return true
    }

    /// Прибрати віджет зі столу (стік у панелі лишається)
    func reattach(_ sticker: Sticker) {
        sticker.isFloating = false
        sticker.updatedAt = .now
        reconcile(sticker)
    }

    /// Єдина точка істини: привести вікно у відповідність до стану стіка.
    /// Викликається з дій, зі спостерігачів у DesktopStickyView (видалення/
    /// архів з панелі) і при відновленні.
    func reconcile(_ sticker: Sticker) {
        // Фізично видалений @Model — властивостей не торкатися (креш)
        guard !sticker.isDeleted else { return }
        let shouldExist = sticker.isFloating && sticker.deletedAt == nil
            && !sticker.archived
        if shouldExist, controllers[sticker.id] == nil {
            // Ліміт тут НЕ перевіряємо: цей шлях — відновлення/undo,
            // мовчки загубити віджет гірше за тимчасовий 11-й
            controllers[sticker.id] = DesktopStickyController(
                sticker: sticker, cascadeIndex: controllers.count)
        } else if !shouldExist, let controller = controllers.removeValue(forKey: sticker.id) {
            controller.close()
        }
    }
}
