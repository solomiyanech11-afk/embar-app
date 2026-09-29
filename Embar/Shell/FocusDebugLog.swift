//
//  FocusDebugLog.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВО (P2.24, діагностика 2026-09-03): траса фокуса й виділення
//  в живому застосунку. Працює ЛИШЕ в пісочниці (SandboxEnvironment).
//  Прибрати разом із закриттям P2.24.
//
//  Логує в консоль Xcode і в unified log (NSLog), префікс [P224]:
//  · кожен makeFirstResponder панелі - хто саме стає відповідачем;
//  · кожну зміну виділення БУДЬ-ЯКОГО NSTextView процесу - клас вьюхи,
//    чи це наш field editor, діапазон, чий текст;
//  · рішення EmbarFieldEditor.initialSelection (пропустив/згорнув);
//  · чи знайшов ClickOnlyFocusGuard справжнє поле назви.
//
//  Зібрати після відтворення: скопіювати [P224]-рядки з консолі Xcode
//  або `log show --predicate 'eventMessage CONTAINS "[P224]"' --last 5m`.
//

import AppKit

enum FocusDebugLog {
    static let enabled = SandboxEnvironment.isActive

    /// Мілісекунди від старту процесу - видно, що вклалось в один кадр
    private static let started = ProcessInfo.processInfo.systemUptime

    static func log(_ message: String) {
        // #if DEBUG: щоб і сам рядок формату [P224] не потрапляв у
        // релізний бінарник (аудит перед TestFlight 2026-09-05)
        #if DEBUG
        guard enabled else { return }
        let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        NSLog("[P224 %7dms] %@", ms, message)
        #endif
    }

    /// Обʼєднаний підпис вьюхи: клас (+ field editor?) + чий текст
    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        if let tv = responder as? NSTextView {
            var parts = ["\(type(of: tv))"]
            if tv.isFieldEditor { parts.append("fieldEditor") }
            parts.append("selection=\(tv.selectedRange())")
            if let field = tv.delegate as? NSTextField {
                parts.append("поле=\(type(of: field)) «\(preview(field.stringValue))»")
            } else if let d = tv.delegate {
                parts.append("делегат=\(type(of: d))")
            }
            parts.append("текст «\(preview(tv.string))»")
            return parts.joined(separator: ", ")
        }
        if let field = responder as? NSTextField {
            return "\(type(of: field)) «\(preview(field.stringValue))»"
        }
        return String(describing: type(of: responder))
    }

    private static func preview(_ s: String) -> String {
        s.count > 24 ? String(s.prefix(24)) + "…" : s
    }

    private static var observer: NSObjectProtocol?

    /// Викликається з EmbarApp.init (лише в пісочниці): вішає спостерігач
    /// на зміни виділення ВСІХ NSTextView процесу
    @MainActor
    static func install() {
        guard enabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: nil, queue: .main) { note in
            guard let tv = note.object as? NSTextView else { return }
            log("selectionChanged: \(describe(tv))")
        }
        log("трасу фокуса увімкнено (пісочниця)")
    }
}
