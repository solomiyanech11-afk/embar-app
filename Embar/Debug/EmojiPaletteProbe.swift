#if DEBUG
//
//  EmojiPaletteProbe.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВИЙ діагностичний зонд для P2.33 (палітра емоджі в Рідері).
//  `-SandboxEmojiProbe YES` (лише пісочниця): відкриває системну палітру
//  над сфокусованим композером і пише в Documents/emoji-probe.log, що
//  відбувається з вікнами, фокусом і видимістю панелі. Буде видалений
//  після діагнозу.
//

import AppKit

@MainActor
enum EmojiPaletteProbe {
    private static var lines: [String] = []
    private static var start = Date()

    private static func log(_ s: String) {
        let t = String(format: "%6.2f", Date().timeIntervalSince(start))
        lines.append("[\(t)] \(s)")
    }

    private static func snapshot(_ tag: String) {
        let panel = NSApp.windows.first { $0 is EmbarPanel }
        let fr = panel?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let front = NSWorkspace.shared.frontmostApplication
        log("\(tag): front=\(front?.bundleIdentifier ?? "nil") active=\(NSApp.isActive) key=\(NSApp.keyWindow?.className ?? "nil") panelVisible=\(panel?.isVisible ?? false) panelX=\(Int(panel?.frame.minX ?? -1)) firstResponder=\(fr)")
        for w in NSApp.windows where w.isVisible {
            log("   вікно: \(String(describing: type(of: w))) frame=\(NSStringFromRect(w.frame)) key=\(w.isKeyWindow) level=\(w.level.rawValue)")
        }
    }

    private static func warp(to point: CGPoint, screen: NSScreen) {
        // NS (низ-ліво) → CG (верх-ліво головного екрана)
        let mainH = NSScreen.screens[0].frame.maxY
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: mainH - point.y))
    }

    static func runIfRequested() {
        guard SandboxEnvironment.isActive, LaunchArgs.flag("SandboxEmojiProbe") else { return }
        start = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            guard let panel = NSApp.windows.first(where: { $0 is EmbarPanel }),
                  let screen = panel.screen ?? NSScreen.main else {
                log("панелі нема"); flush(); return
            }
            // Курсор у центр панелі — «зайшли мишею»
            warp(to: CGPoint(x: panel.frame.midX, y: panel.frame.midY), screen: screen)
            try? await Task.sleep(for: .seconds(0.5))
            snapshot("до палітри (курсор у панелі)")

            // Клавіатура панелі + палітра
            panel.makeKey()
            try? await Task.sleep(for: .seconds(0.3))
            snapshot("після makeKey")
            NSApp.orderFrontCharacterPalette(nil)
            for i in 1...4 {
                try? await Task.sleep(for: .seconds(0.5))
                snapshot("палітра відкрита +\(Double(i)/2)с")
            }

            // Курсор геть із панелі (ліворуч, повз палітру)
            warp(to: CGPoint(x: panel.frame.minX - 400, y: panel.frame.midY), screen: screen)
            log("курсор варпнуто за межі панелі")
            for i in 1...4 {
                try? await Task.sleep(for: .seconds(0.5))
                snapshot("після виходу курсора +\(Double(i)/2)с")
            }
            flush()
        }
    }

    private static func flush() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? lines.joined(separator: "\n").appending("\n")
            .write(to: docs.appendingPathComponent("emoji-probe.log"),
                   atomically: true, encoding: .utf8)
        log("готово")
    }
}

#endif
