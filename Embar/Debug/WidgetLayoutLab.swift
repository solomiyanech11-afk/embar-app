#if DEBUG
//
//  WidgetLayoutLab.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВИЙ debug-стенд (2026-07-30, за зразком GlassLab): візуальна
//  матриця інваріанта розкладки тексту віджетів (SPEC §2.7) — СПРАВЖНЯ
//  DesktopStickyView у рамках, що емулюють розміри вікна (показ-обрізання
//  залежить лише від запропонованого розміру, тож рамка = чесна емуляція).
//  Запуск `-WidgetLayoutLab YES`: PNG у Documents і вихід.
//  Видалити після приймання рефакторингу.
//

import SwiftUI
import SwiftData
import AppKit

enum WidgetLayoutLab {
    static var isRequested: Bool {
        LaunchArgs.flag("WidgetLayoutLab")
    }

    private static var window: NSWindow?

    @MainActor static func run() {
        let hosting = NSHostingView(rootView: WidgetLayoutLabView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Widget Layout Lab"
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capture(window: window, filename: "widgetlayoutlab.png")
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func capture(window: NSWindow?, filename: String) {
        guard let w = window else { return }
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        let id = CGWindowID(w.windowNumber)
        if let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, id,
            [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                NSLog("WidgetLayoutLab: captured -> \(url.path)")
            }
        }
    }
}

@MainActor
private struct WidgetLayoutLabView: View {
    // In-memory стор: лабораторні стіки не торкаються реальної бази
    private let container: ModelContainer
    private let shortSticker: Sticker
    private let longSticker: Sticker
    private let fullSticker: Sticker
    private let fullLongSticker: Sticker

    init() {
        container = try! ModelContainer(
            for: Sticker.self, Wall.self, Note.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let long = Array(repeating:
            "Довгий текст який точно не влізе у вікно навіть на максимальній висоті",
            count: 8).joined(separator: " ")

        shortSticker = Sticker(text: "Купити квіти мамі", colorIndex: 0)
        longSticker = Sticker(text: long, colorIndex: 1)
        fullSticker = Sticker(text: long, colorIndex: 2)
        fullSticker.bodyText = "коротке тіло"
        fullSticker.floatDisplayMode = "full"
        fullLongSticker = Sticker(text: long, colorIndex: 3)
        fullLongSticker.bodyText = long
        fullLongSticker.floatDisplayMode = "full"
        for s in [shortSticker, longSticker, fullSticker, fullLongSticker] {
            container.mainContext.insert(s)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "7a2c3c"), Color(hex: "c2554f"),
                                    Color(hex: "2b3a2e")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .top, spacing: 18) {
                cell("1 · короткий, авто\n→ повний, без «…»",
                     shortSticker, w: 160, h: 76)
                cell("2 · короткий, розтягнуте 300\n→ повний + чесна порожнеча",
                     shortSticker, w: 160, h: 300)
                cell("3 · довгий, стеля 420\n→ «…» внизу, без порожнечі",
                     longSticker, w: 190, h: 420)
                cell("4 · довгий full, тіло коротке\n→ титул пріоритет, тіло після",
                     fullSticker, w: 190, h: 420)
                cell("5 · обидва довгі, стеля\n→ тіло обрізається першим",
                     fullLongSticker, w: 220, h: 420)
                cell("6 · довгий, широке 380\n→ влазить більше, «…» пізніше",
                     longSticker, w: 380, h: 420)
            }
            .padding(20)
        }
        .modelContainer(container)
    }

    private func cell(_ label: String, _ sticker: Sticker,
                      w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.emUI(10, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 3)
            DesktopStickyView(sticker: sticker)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 0)
        }
        .frame(width: max(w, 150))
    }
}

#endif
