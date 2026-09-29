//
//  ComposerGlass.swift
//  Embar
//
//  Спільне «рідке скло» композерів (поле стіків, compose рідера) —
//  винесено з QuickComposer 2026-07-21, щоб обидві поверхні мали
//  ІДЕНТИЧНУ конструкцію і калібрування.
//

import SwiftUI
import AppKit

/// VEV-скло: withinWindow-blur із прибитим станом. Пресети VEV сірять —
/// тому найсвітліший матеріал + буст насичення бекдропа (див. нижче)
struct WithinWindowGlass: NSViewRepresentable {
    var cornerRadius: CGFloat = 22
    var material: NSVisualEffectView.Material = .menu
    /// «Рідкість» скла: кольори за склом світяться (CSS saturate(1.5)).
    /// nil — стандартне насичення матеріалу
    var saturation: CGFloat? = nil
    /// Прибрати власне «молоко» матеріалу (шари fill 60–84% + сірий tone):
    /// лишається чистий blur+saturate, білість добираємо своїм тінтом
    var stripsMaterialTint: Bool = false

    func makeNSView(context: Context) -> SaturatedGlassView {
        let view = SaturatedGlassView()
        view.blendingMode = .withinWindow
        view.state = .active   // панель nonactivating — без цього сіре
        view.material = material
        view.saturationBoost = saturation
        view.stripsTint = stripsMaterialTint
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: SaturatedGlassView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.material = material
        view.saturationBoost = saturation
        view.stripsTint = stripsMaterialTint
    }
}

/// VEV, що підкручує «colorSaturate»-фільтр власного backdrop-шару.
/// Публічного API насичення у VEV немає; CIFilter-и на шарах усередині
/// NSHostingView не рендеряться (перевірено 2026-07-19) — тому єдиний
/// робочий шлях: знайти готовий фільтр матеріалу і змінити його amount.
/// Якщо фільтра немає (матеріал без вбудованого насичення) — тихо нічого,
/// вигляд просто лишається стандартним
final class SaturatedGlassView: NSVisualEffectView {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    var saturationBoost: CGFloat? {
        didSet { if saturationBoost != oldValue { applyTuning() } }
    }
    var stripsTint: Bool = false {
        didSet { if stripsTint != oldValue { applyTuning() } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Backdrop-шар зʼявляється після вставки у вікно — застосовуємо
        // на наступному циклі, коли AppKit добудує дерево шарів
        DispatchQueue.main.async { [weak self] in self?.applyTuning() }
    }

    // AppKit перебудовує шари матеріалу в updateLayer (зміна appearance
    // тощо) — повторюємо наше налаштування після кожної перебудови
    override func updateLayer() {
        super.updateLayer()
        applyTuning()
    }

    private func applyTuning() {
        guard let layer else { return }
        func walk(_ l: CALayer) {
            // Молоко матеріалу: fill (біле 60–84%) + tone (сірий) — гасимо,
            // якщо просили чисте скло
            if stripsTint, l.name == "fill" || l.name == "tone" {
                l.isHidden = true
            }
            if let amount = saturationBoost,
               var filters = l.filters, !filters.isEmpty {
                var touched = false
                for f in filters {
                    let obj = f as AnyObject
                    if (obj.value(forKey: "name") as? String) == "colorSaturate" {
                        obj.setValue(amount, forKey: "inputAmount")
                        touched = true
                    }
                }
                // Перепризначення масиву змушує CA перечитати фільтри
                if touched { l.filters = filters }
            }
            (l.sublayers ?? []).forEach(walk)
        }
        walk(layer)
    }
}

/// Готовий скляний фон композера — той самий вигляд на стіках і в рідері.
///
/// ⏯ Перемикач (2026-07-20, рішення користувача): true — нативний Liquid
/// Glass (справжнє заломлення, але трохи біліє при першому кліку — слухає
/// key-нотифікації вікна, API стану немає); false — VEV із прибитим
/// .state = .active (стабільний у фокусі й без). Обидві гілки лишаємо —
/// рішення ще не фінальне
struct ComposerGlassBackdrop: View {
    var cornerRadius: CGFloat = 12
    /// Додаткове біле «молоко» поверх скла (0 — чисте скло, як у стіків).
    /// Compose рідера бере ~0.3: він лежить на світлій панелі і без цього
    /// зливається з фоном (фідбек 2026-07-21)
    var milk: Double = 0

    private static let useNativeLiquidGlass = true

    var body: some View {
        if Self.useNativeLiquidGlass, #available(macOS 26.0, *) {
            ZStack {
                Color.clear
                    .glassEffect(.regular.tint(.white.opacity(0.12)),
                                 in: .rect(cornerRadius: cornerRadius))
                if milk > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.white.opacity(milk))
                }
            }
        } else {
            // VEV-гілка, калібр 2026-07-20 (GlassLab): власне молоко
            // матеріалу погашено (шари fill/tone і були «сірою плитою»),
            // насичення бекдропа 1.5 — кольори світяться крізь blur,
            // білість добирає лише тонке молоко 0.13
            ZStack {
                WithinWindowGlass(cornerRadius: cornerRadius, saturation: 1.5,
                                  stripsMaterialTint: true)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.13 + milk))
            }
            // Кант: зверху яскравіший (highlight), донизу мʼякший
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
    }
}
