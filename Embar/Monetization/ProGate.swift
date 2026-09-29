//
//  ProGate.swift
//  Embar
//
//  Однорядковий гейт створення для режиму читання (SPEC §15.77ґ).
//
//  Використання на КОЖНІЙ точці створення з карти:
//      guard ProGate.allowCreate() else { return }
//  Відмова не мовчазна: гейт сам показує undo-тост «Режим читання…»
//  з кнопкою «Дізнатись більше», що відкриває пейвол, - усі точки
//  поводяться ідентично.
//
//  ❗ Гейт мусить стояти ПЕРЕД будь-яким очищенням поля вводу: людина
//  написала текст, отримала тост - текст лишився в композері
//  (рішення 2026-09-16).
//
//  Карту точок тримає source-scan у ProGateTests: файл із карти без
//  виклику ProGate.allowCreate не пройде CI.
//

import Foundation

@MainActor
enum ProGate {
    /// true - створюй; false - показано тост, створення заборонене
    static func allowCreate() -> Bool {
        guard !EntitlementStore.shared.canCreate else { return true }
        NotificationCenter.default.post(
            name: .embarUndoToast, object: nil,
            userInfo: [
                "message": LocalizedStringResource(
                    "Режим читання: пробний період завершився",
                    comment: "Тост при спробі створити нове після trial"),
                "actionLabel": LocalizedStringResource(
                    "Дізнатись більше",
                    comment: "Кнопка тосту режиму читання: відкриває пейвол"),
                "action": ToastCenter.UndoAction {
                    PaywallWindowController.shared.show()
                },
            ])
        return false
    }
}
