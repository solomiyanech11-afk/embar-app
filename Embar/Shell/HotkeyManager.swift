//
//  HotkeyManager.swift
//  Embar
//
//  Глобальний хоткей показу/приховання панелі. Дефолт — Option+E
//  (SPEC §15 п.14); з Settings можна вимкнути або записати свою
//  комбінацію (2026-07-19) — зберігається в UserDefaults, перереєстрація
//  на льоту через .embarHotkeyChanged.
//  Carbon RegisterEventHotKey: працює глобально без спец-дозволів (на відміну
//  від CGEvent-tap, який потребує Accessibility).
//

import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Хоткей змінили в Settings (toggle/нова комбінація) — перереєструвати
    static let embarHotkeyChanged = Notification.Name("embar.hotkeyChanged")
}

final class HotkeyManager {
    // Ключі UserDefaults (читає і Settings-UI)
    static let enabledKey = "hotkeyEnabled"
    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"   // Carbon-маска
    static let displayKey = "hotkeyDisplay"       // напр. "⌥E"

    /// Відсутній ключ = дефолт увімкнено
    static var isEnabled: Bool {
        let d = EmbarDefaults.store
        return d.object(forKey: enabledKey) == nil || d.bool(forKey: enabledKey)
    }
    static var keyCode: UInt32 {
        let d = EmbarDefaults.store
        return d.object(forKey: keyCodeKey) == nil
            ? UInt32(kVK_ANSI_E) : UInt32(d.integer(forKey: keyCodeKey))
    }
    static var modifiers: UInt32 {
        let d = EmbarDefaults.store
        return d.object(forKey: modifiersKey) == nil
            ? UInt32(optionKey) : UInt32(d.integer(forKey: modifiersKey))
    }
    static var display: String {
        EmbarDefaults.store.string(forKey: displayKey) ?? "⌥E"
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
        installHandler()
        applyFromDefaults()
        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyChanged),
            name: .embarHotkeyChanged, object: nil)
    }

    @objc private func hotkeyChanged() { applyFromDefaults() }

    /// Єдине місце правди: зняти стару реєстрацію, поставити поточну
    /// (або нічого, якщо вимкнено)
    private func applyFromDefaults() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard Self.isEnabled else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x454D4252), id: 1) // 'EMBR'
        RegisterEventHotKey(Self.keyCode, Self.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Carbon-handler ставиться один раз на життя обʼєкта
    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onFire()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    nonisolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
