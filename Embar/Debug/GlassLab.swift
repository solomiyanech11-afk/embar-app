#if DEBUG
//
//  GlassLab.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВИЙ debug-стенд (2026-07-20): порівняння VEV-матеріалів для
//  скла композера. Запускається ЛИШЕ з аргументом `-GlassLab YES`,
//  знімає власне вікно у PNG (Documents контейнера) і закривається.
//  Видалити після калібрування.
//

import SwiftUI
import AppKit

enum GlassLab {
    static var isRequested: Bool {
        LaunchArgs.flag("GlassLab")
    }

    private static var window: NSWindow?

    @MainActor static func run() {
        let hosting = NSHostingView(rootView: GlassLabView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
            styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Glass Lab"
        // Як у реальній панелі (PanelController): завжди світла тема,
        // інакше VEV-матеріали в системному дарк-моді стають темною плитою
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        // Даємо WindowServer час скомпозитити backdrop-blur, тоді знімаємо
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capture(window: window, filename: "glasslab.png")
            NSApp.terminate(nil)
        }
    }

    /// Режим `-GlassShot YES`: звичайний запуск, знімок РЕАЛЬНОЇ панелі
    /// (зібраний вигляд поля над справжніми стіками) і вихід
    static var isShotRequested: Bool {
        LaunchArgs.flag("GlassShot")
    }

    @MainActor static func shootRealPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Саме EmbarPanel: поруч живуть прозорі службові вікна
            // (shadowWindow ширший за панель — «найбільше» дає чорний кадр)
            let target = NSApp.windows.first {
                $0.isVisible && String(describing: type(of: $0)) == "EmbarPanel"
            }
            capture(window: target, filename: "glassshot.png")
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func capture(window: NSWindow?, filename: String) {
        guard let w = window else { return }
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)

        // Знімок ВЛАСНОГО вікна — дозволу Screen Recording не потребує
        let id = CGWindowID(w.windowNumber)
        if let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, id,
            [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                NSLog("GlassLab: captured window -> \(url.path)")
                return
            }
        }
        // Fallback: рендер вʼюхи без композитингу (blur не покаже, але
        // хоч layout буде видно)
        if let view = w.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                NSLog("GlassLab: FALLBACK cacheDisplay -> \(url.path)")
            }
        }
    }
}

/// Мок стіни стіків + 4 варіанти скла. Кожне поле лежить половиною над
/// порожнім фоном панелі, половиною над кольоровими стіками — рівно три
/// критерії калібрування в одному кадрі
private struct GlassLabView: View {
    enum Kind {
        case vev(NSVisualEffectView.Material, CGFloat?, strip: Bool)
        case ciFilter
    }
    // Варіанти: чисте скло (fill/tone погашені) з різним насиченням
    // + контроль без стрипу
    private let variants: [(label: String, kind: Kind)] = [
        ("A  .menu, sat 1.5, чисте", .vev(.menu, 1.5, strip: true)),
        ("B  .menu, sat 1.8, чисте", .vev(.menu, 1.8, strip: true)),
        ("C  .popover, sat 1.5, чисте", .vev(.popover, 1.5, strip: true)),
        ("D  .menu, sat 1.5, як є (контроль)", .vev(.menu, 1.5, strip: false)),
    ]
    // Cream-палітра (яскраві) + панельний фон з прототипу
    private let stickyColors = ["#fef9c3", "#dbeafe", "#dcfce7", "#fce7f3", "#ede9fe"]

    var body: some View {
        VStack(spacing: 22) {
            ForEach(Array(variants.enumerated()), id: \.offset) { _, v in
                variantRow(v.label, v.kind)
            }
        }
        .padding(.vertical, 24)
        .frame(width: 460)
        .background(Color(hex: "#fcfbf9"))
    }

    private func variantRow(_ label: String, _ kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
                .padding(.leading, 20)
            ZStack {
                // Права половина — соковиті стіки, ліва — порожній фон
                HStack(spacing: 8) {
                    Spacer().frame(width: 190)
                    ForEach(Array(stickyColors.enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color(hex: hex))
                            .frame(width: 52, height: 84)
                    }
                }
                // Поле-макет: та сама конструкція, що в QuickComposer
                HStack {
                    Text("Записати думку…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#6f6f68"))
                        .padding(.leading, 18)
                    Spacer()
                    Circle().fill(.black).frame(width: 27, height: 27)
                        .overlay(Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white))
                        .padding(.trailing, 9)
                }
                .frame(height: 46)
                .background(
                    ZStack {
                        glassLayer(kind)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.13))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.75), .white.opacity(0.4)],
                            startPoint: .top, endPoint: .bottom), lineWidth: 1))
                )
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private func glassLayer(_ kind: Kind) -> some View {
        switch kind {
        case .vev(let material, let sat, let strip):
            WithinWindowGlass(cornerRadius: 12, material: material,
                              saturation: sat, stripsMaterialTint: strip)
        case .ciFilter:
            CIFilterGlass(cornerRadius: 12)
        }
    }
}

/// Ретест підходу ae8342e: чистий CALayer.backgroundFilters (blur + sat)
/// без VEV. 2026-07-19 висновок був «не малює blur у NSHostingView» —
/// перевіряємо ще раз у контрольованих умовах
private struct CIFilterGlass: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        if let layer = view.layer {
            var filters: [Any] = []
            if let saturate = CIFilter(name: "CIColorControls") {
                saturate.setDefaults()
                saturate.setValue(1.8, forKey: kCIInputSaturationKey)
                filters.append(saturate)
            }
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(14, forKey: kCIInputRadiusKey)
                filters.append(blur)
            }
            layer.backgroundFilters = filters
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

#endif
