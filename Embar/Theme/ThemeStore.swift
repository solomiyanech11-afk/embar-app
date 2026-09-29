//
//  ThemeStore.swift
//  Embar
//
//  Активна палітра + матеріальність панелі (DESIGN-DIRECTIONS §1).
//  Вибір зберігається між запусками (@AppStorage — аналог
//  localStorage['quicknote.palette'] у прототипі).
//

import SwiftUI
import Combine

extension Notification.Name {
    /// Матеріальність змінилась — PanelController перемикає AppKit-blur
    /// (за зразком .embarPanelDidShow; UserDefaults.didChange заголосний)
    static let embarMaterialChanged = Notification.Name("embar.materialChanged")
}

@MainActor
final class ThemeStore: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    // ❗ НЕ @AppStorage. Всередині класу цей обгортка завжди пише в
    // UserDefaults.standard: `.defaultAppStorage(...)` живе в оточенні
    // SwiftUI і до звичайного обʼєкта не доходить. Через це в пісочниці
    // палітра й фон панелі писались у РЕАЛЬНІ налаштування, а читались
    // із суїту - кружечки «фон панелі» просто не діяли, бо запис і
    // читання ходили в різні місця (баг 2026-08-11).
    //
    // Тому тут звичайні обчислювані властивості над EmbarDefaults.store -
    // тим самим входом, яким користується решта не-View коду.

    private var defaults: UserDefaults { EmbarDefaults.store }

    private var paletteSlug: String {
        get { defaults.string(forKey: "palette") ?? Palette.defaultSlug }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "palette")
        }
    }

    // Матеріальність (Glass-тема): вибір + прозорість «молока» 0…1
    private var materialThemeRaw: String {
        get { defaults.string(forKey: "materialTheme") ?? MaterialTheme.opaque.rawValue }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "materialTheme")
            NotificationCenter.default.post(name: .embarMaterialChanged, object: nil)
        }
    }

    /// Молочний тінт поверх скла: 0 = чисте Apple-скло (матеріал сам
    /// несе frost+blur), 1 = опакне молоко. Дефолт низький → скляно
    var glassOpacity: Double {
        get {
            defaults.object(forKey: "glassOpacity") as? Double ?? 0.12
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "glassOpacity")
        }
    }

    /// Відтінок фону панелі (Settings «фон панелі») — сам колір читається
    /// через EmbarColors.surface; тут лише тригер перерендеру
    var panelSurfaceRaw: String {
        get { defaults.string(forKey: "panelSurface") ?? PanelSurface.warm.rawValue }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "panelSurface")
        }
    }

    var current: Palette {
        Palette.bySlug(paletteSlug)
    }

    func select(_ palette: Palette) {
        paletteSlug = palette.slug
    }

    var materialTheme: MaterialTheme {
        get { MaterialTheme(rawValue: materialThemeRaw) ?? .opaque }
        set { materialThemeRaw = newValue.rawValue }
    }

    /// Скло й Левітацію вимкнено в UI (2026-08-11, «працюють погано»),
    /// але хто встиг їх обрати - лишався на зламаному матеріалі, і
    /// сегмент показував його активним, хоч клік казав «скоро»
    /// (code review 2026-08-12 №3). Викликати при старті.
    static func migrateDisabledMaterialsIfNeeded() {
        let defaults = EmbarDefaults.store
        let raw = defaults.string(forKey: "materialTheme")
        guard raw == MaterialTheme.glass.rawValue
            || raw == MaterialTheme.levitation.rawValue else { return }
        defaults.set(MaterialTheme.opaque.rawValue, forKey: "materialTheme")
        NotificationCenter.default.post(name: .embarMaterialChanged, object: nil)
        NSLog("Embar: матеріал %@ вимкнено - повернуто Звичайну", raw ?? "?")
    }
}
