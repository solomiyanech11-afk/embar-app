#if DEBUG
//
//  EmptyStatesLab.swift
//  Embar
//
//  ⚠️ ТИМЧАСОВИЙ debug-стенд (2026-08-02): аркуш УСІХ порожніх станів
//  (SPEC §8.1) справжніми компонентами — щоб правити тексти, бачачи
//  типографіку і сусідство. Запуск `-EmptyStatesLab YES`: PNG у
//  Documents контейнера і вихід. Видалити після редагування копірайту.
//

import SwiftUI
import AppKit

enum EmptyStatesLab {
    static var isRequested: Bool {
        LaunchArgs.flag("EmptyStatesLab")
    }

    private static var window: NSWindow?

    @MainActor static func run() {
        let hosting = NSHostingView(rootView: EmptyStatesLabView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 1760),
            styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Empty States"
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            capture(window: window, filename: "empty-states.png")
            NSApp.terminate(nil)
        }
    }

    @MainActor private static func capture(window: NSWindow?, filename: String) {
        guard let w = window, let view = w.contentView else { return }
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        // Рендер вʼюхи (не вікна) — беремо повну висоту без обрізання
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: docs.appendingPathComponent(filename))
            NSLog("EmptyStatesLab: captured -> \(docs.path)/\(filename)")
        }
    }
}

private struct EmptyStatesLabView: View {
    /// Кожен випадок: номер, де живе, коли зʼявляється, сама вʼюха
    private struct Case: Identifiable {
        let id: Int
        let place: String
        let when: String
        let view: AnyView
    }

    private var cases: [Case] {
        var n = 0
        func next(_ place: String, _ when: String,
                  @ViewBuilder _ view: () -> some View) -> Case {
            n += 1
            return Case(id: n, place: place, when: when, view: AnyView(view()))
        }
        return [
            next("Стіки · стіна", "стіків немає взагалі") {
                EmptyStateText(line1: "Поки порожньо.",
                               line2: "Напиши першу думку, щоб не загубити.")
            },
            next("Стіки · фільтр / стіна / архів", "фільтр не дав результату") {
                Text("Тут нічого немає.")
                    .font(.emUI(12.5)).foregroundStyle(EmbarColors.ink3)
            },
            next("Нотатки · список", "нотаток немає взагалі") {
                EmptyStateText(line1: "Нотаток ще немає.",
                               line2: nil)
            },
            next("Нотатки · папка", "у вибраній папці порожньо") {
                Text("У цій папці порожньо.")
                    .font(.emDisplay(13, italic: true))
                    .foregroundStyle(EmbarColors.ink3)
            },
            next("Нотатки · пошук", "пошук без результату") {
                Text("Нічого не знайдено.")
                    .font(.emUI(12.5)).foregroundStyle(EmbarColors.ink3)
            },
            next("Нотатки · беклінки", "нотатку ніхто не згадує") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ТУТ ЗГАДУЄТЬСЯ")
                        .font(.emUI(10, weight: .medium)).tracking(1.4)
                        .foregroundStyle(EmbarColors.ink3)
                    Text("Ця нотатка ніде не згадується. (Напиши [[ в нотатці, щоб зробити звʼязок.)")
                        .font(.emUI(11.5)).foregroundStyle(EmbarColors.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 260, alignment: .leading)
            },
            next("Рідер · полиця", "блокнотів немає") {
                EmptyStateText(line1: "Вивчаєш щось цікаве?",
                               line2: "Створи перший блокнот, щоб нічого не забути.")
            },
            next("Рідер · пошук полиці", "пошук без результату") {
                Text("Нічого не знайдено.")
                    .font(.emUI(13)).foregroundStyle(EmbarColors.ink3)
            },
            next("Рідер · блокнот", "у блокноті ще нема записів") {
                EmptyStateText(line1: "Нотуй, поки читаєш.",
                               line2: "Все залишиться тут.")
            },
            next("Рідер · фільтри блокнота", "перетин фільтрів порожній") {
                Text("Тут нічого немає.")
                    .font(.emUI(13)).foregroundStyle(EmbarColors.ink3)
            },
            next("Home · тудушки «До зробити»", "тека порожня — БЕЗ тексту, лише кнопка") {
                Text("＋ нова тудушка")
                    .font(.emUI(12.5)).foregroundStyle(EmbarColors.ink3.opacity(0.7))
            },
            next("Home · тудушки «Виконано»", "нічого не виконано") {
                HomeEmptyLine("Тут зʼявлятиметься зроблене.")
            },
            next("Home · звички «До зробити»", "усі звички виконано") {
                HomeEmptyLine("Всі звички на сьогодні виконано")
            },
            next("Home · звички «Виконано»", "ще нічого не виконано") {
                HomeEmptyLine("Тут зʼявлятимуться виконані звички.")
            },
            next("Home · таймлайн", "на день немає подій") {
                Text("Подій немає.")
                    .font(.emDisplay(13, italic: true))
                    .foregroundStyle(EmbarColors.ink3)
            },
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Порожні стани Embar · SPEC §8.1")
                    .font(.emDisplay(20, italic: true))
                    .foregroundStyle(EmbarColors.ink)
                    .padding(.bottom, 4)
                Text("Справжні компоненти на справжньому фоні панелі. Номери - як у docs/EMPTY-STATES.md")
                    .font(.emUI(11.5)).foregroundStyle(EmbarColors.ink3)
                    .padding(.bottom, 18)

                ForEach(cases) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Text("\(item.id)")
                            .font(.emUI(12, weight: .semibold))
                            .foregroundStyle(EmbarColors.ink3)
                            .frame(width: 20, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place)
                                .font(.emUI(12, weight: .medium))
                                .foregroundStyle(EmbarColors.ink)
                            Text(item.when)
                                .font(.emUI(10.5))
                                .foregroundStyle(EmbarColors.ink3)
                        }
                        .frame(width: 250, alignment: .leading)

                        item.view
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(EmbarColors.surface))
                    }
                    .padding(.vertical, 9)
                    Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
                }
            }
            .padding(28)
        }
        .background(EmbarColors.bg)
    }
}

#endif
