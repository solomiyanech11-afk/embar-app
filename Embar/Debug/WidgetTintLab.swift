#if DEBUG
//
//  WidgetTintLab.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВИЙ debug-стенд (2026-07-30, за зразком GlassLab): підбір
//  насиченості тінта стилю «колір стіка» у віджетах. Запуск ЛИШЕ з
//  аргументом `-WidgetTintLab YES`: малює 4 варіанти alpha поверх
//  справжніх шпалер (withinWindow-скло — той самий композит, що
//  behindWindow у реального віджета), знімає PNG у Documents і виходить.
//  Видалити після калібрування.
//

import SwiftUI
import AppKit

enum WidgetTintLab {
    static var isRequested: Bool {
        LaunchArgs.flag("WidgetTintLab")
    }

    private static var window: NSWindow?

    @MainActor static func run() {
        let hosting = NSHostingView(rootView: WidgetTintLabView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 520),
            styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Widget Tint Lab"
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capture(window: window, filename: "widgettintlab.png")
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
                NSLog("WidgetTintLab: captured -> \(url.path)")
            }
        }
    }
}

private struct WidgetTintLabView: View {
    private let variants: [Double] = [0.72, 0.80, 0.88, 0.96]
    private let palette = Palette.bySlug("cream")

    var body: some View {
        ZStack {
            wallpaper
            HStack(spacing: 24) {
                ForEach(variants, id: \.self) { alpha in
                    VStack(spacing: 14) {
                        Text(alpha == 0.72
                             ? String(format: "%.2f (зараз)", alpha)
                             : String(format: "%.2f", alpha))
                            .font(.emUI(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        mockCard(color: palette.sticky[0], alpha: alpha)
                        mockCard(color: palette.sticky[1], alpha: alpha)
                    }
                }
            }
            .padding(28)
        }
    }

    /// Справжні шпалери користувача; без доступу — кольоровий градієнт
    @ViewBuilder private var wallpaper: some View {
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Color(hex: "7a2c3c"), Color(hex: "c2554f"),
                                    Color(hex: "2b3a2e")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Мок-віджет: те саме скло, що в реального (withinWindow-варіант
    /// SaturatedGlassView + тінт + кант), типовий текст
    private func mockCard(color: Color, alpha: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("вчора · робота")
                .font(.emUI(10))
                .foregroundStyle(StickyInk.on(color).ink3)
            Text("Купити квіти мамі до неділі")
                .font(.emUI(14))
                .foregroundStyle(StickyInk.on(color).ink)
                .padding(.top, 6)
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .background(
            ZStack {
                WithinWindowGlass(cornerRadius: 12, saturation: 1.5,
                                  stripsMaterialTint: true)
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(alpha))
            }
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1))
        )
    }
}

#endif
