//
//  ToastCenter.swift
//  Embar
//
//  Централізований показ тостів (SPEC §7.2, §8.2):
//  · mini — коротке підтвердження («Додано в тудушки ✓»), ~2.2с
//  · undo — світла пігулка з дією і drain-ring-таймером (5с), для видалень
//
//  Один активний тост кожного типу; новий витісняє попередній.
//

import SwiftUI
import Combine

extension Notification.Name {
    /// Mini-тост із будь-якого місця: userInfo ["text": LocalizedStringResource,
    /// "seconds": Double?]
    static let embarMiniToast = Notification.Name("embarMiniToast")
    /// Undo-тост із не-View місць: userInfo ["message": LocalizedStringResource,
    /// "action": ToastCenter.UndoAction] (2026-07-29, фото нотаток)
    static let embarUndoToast = Notification.Name("embarUndoToast")
}

@MainActor
final class ToastCenter: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    // Тексти тостів — LocalizedStringResource, а не String: тост живе в
    // моделі й малюється пізніше, тож переклад має підбиратись у момент
    // показу, а не збиратись рядком у місці виклику (i18n 2026-08-03)
    struct Mini: Identifiable, Equatable {
        let id = UUID()
        let text: LocalizedStringResource
        /// danger — червона пігулка для помилок («дата вже минула»)
        var style: Style = .neutral
    }

    enum Style { case neutral, danger }

    struct Undo: Identifiable {
        let id = UUID()
        let message: LocalizedStringResource
        let actionLabel: LocalizedStringResource
        let duration: Double
        /// Викликається при натисканні дії (напр. відновлення soft-deleted)
        let action: () -> Void
        /// Момент показу — для розрахунку залишку drain-ring
        let shownAt: Date = .now
    }

    @Published private(set) var mini: Mini?
    @Published private(set) var undo: Undo?

    private var miniTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

    /// Обгортка замикання для userInfo нотифікації (Any не кастується
    /// в функцію напряму).
    /// ❗ СТРУКТУРА, не клас: у класу під default-isolation MainActor deinit
    /// стає ізольованим, і його back-deploy шлях у рантаймі
    /// (swift_task_deinitOnExecutor… → TaskLocal::StopLookupScope) звільняє
    /// чужий вказівник, коли останнє посилання відпускається всередині
    /// Task — купа псується, далі падіння/фриз у довільному місці
    /// (блокер тест-плану 2026-08-25, ASan; той самий підпис у крашах
    /// StickyHeightEstimator 2026-08-18). У структури deinit немає взагалі
    struct UndoAction {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    init() {
        // Тости з не-View місць (NoteImageStore тощо): нотифікація з
        // текстом → mini-тост (2026-07-29, підказка про файл-пікер)
        NotificationCenter.default.addObserver(
            forName: .embarMiniToast, object: nil, queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? LocalizedStringResource
            else { return }
            let seconds = note.userInfo?["seconds"] as? Double ?? 2.2
            self?.showMini(text, seconds: seconds)
        }
        NotificationCenter.default.addObserver(
            forName: .embarUndoToast, object: nil, queue: .main
        ) { [weak self] note in
            guard let message = note.userInfo?["message"] as? LocalizedStringResource,
                  let action = note.userInfo?["action"] as? UndoAction
            else { return }
            // Опційний власний підпис кнопки: ProGate шле «Дізнатись
            // більше» замість дефолтного «Скасувати» (SPEC §15.77ґ)
            if let label = note.userInfo?["actionLabel"] as? LocalizedStringResource {
                self?.showUndo(message: message, actionLabel: label) { action.run() }
            } else {
                self?.showUndo(message: message) { action.run() }
            }
        }
    }

    // MARK: - Mini

    func showMini(_ text: LocalizedStringResource, seconds: Double = 2.2,
                  style: Style = .neutral) {
        miniTask?.cancel()
        mini = Mini(text: text, style: style)
        let id = mini!.id
        miniTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if self?.mini?.id == id { self?.mini = nil }
        }
    }

    // MARK: - Undo

    /// `actionLabel` має власний ключ: те саме «Скасувати» в діалозі означає
    /// Cancel, а тут — Undo (i18n 2026-08-03)
    func showUndo(message: LocalizedStringResource,
                  actionLabel: LocalizedStringResource = .init(
                    "toast.action.undo", defaultValue: "Скасувати",
                    comment: "Кнопка в undo-тості: повернути щойно видалене"),
                  duration: Double = 5, action: @escaping () -> Void) {
        undoTask?.cancel()
        undo = Undo(message: message, actionLabel: actionLabel, duration: duration, action: action)
        let id = undo!.id
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if self?.undo?.id == id { self?.undo = nil }
        }
    }

    /// Натиснута дія в undo-тості
    func performUndo() {
        undoTask?.cancel()
        let action = undo?.action
        undo = nil
        action?()
    }

    func dismissUndo() {
        undoTask?.cancel()
        undo = nil
    }
}
