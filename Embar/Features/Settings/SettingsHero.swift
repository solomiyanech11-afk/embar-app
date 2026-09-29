//
//  SettingsHero.swift
//  Embar
//
//  Hero-карусель налаштувань (прототип .settings-hero, 210px): фото-картки
//  full-bleed з білим градієнтом знизу, титул Inter light + Fraunces-em,
//  крапки, автогортання кожні 3.5с (слайд 0.55s). Hidden Gems відкриває
//  сабсторінку (стрілка ↗); Community неактивна з пігулкою «Скоро» -
//  лінків спільноти ще немає (2026-09-19).
//

import SwiftUI
import Combine

private struct HeroCard: Identifiable {
    let id: Int
    let image: String
    let title: AnyView
    let sub: LocalizedStringKey
    /// Клікабельна картка відкриває сабсторінку (стрілка ↗ у куті)
    var subpage: SettingsSubpage.Kind? = nil
    /// Пігулка в куті замість стрілки: картка не клікається, а чесно
    /// каже «скоро» (Community, 2026-09-19)
    var badge: LocalizedStringKey? = nil
}

struct SettingsHero: View {
    /// Сабсторінка відкрита — карусель на паузі (прототип pause carousel)
    var paused = false
    var onOpenSubpage: (SettingsSubpage.Kind) -> Void = { _ in }
    @State private var slide = 0
    /// Автогортання (прототип _settingsSlideDur = 3500)
    private let timer = Timer.publish(every: 3.5, on: .main, in: .common)
        .autoconnect()
    /// Імʼя користувача. Поки порожнє — поле вводу зʼявиться разом
    /// з онбордингом; тоді картка оновиться сама
    @AppStorage(HeroGreeting.storageKey) private var userName = ""

    /// «Hey, Ім'я» або просто «Hey», якщо імені ще не задали.
    ///
    /// Два `Text` замість одного рядка з підстановкою — бо привітання й
    /// імʼя мальовані РІЗНИМИ шрифтами (Inter light + Fraunces italic),
    /// як em/strong у прототипі. Імʼя йде через `Text(verbatim:)`:
    /// це дані користувача, перекладати його не можна.
    private var greeting: Text {
        guard let name = HeroGreeting.name(from: userName) else {
            return Text("Hey").fontWeight(.light)
        }
        return Text("Hey, ").fontWeight(.light)
            + Text(verbatim: name).font(.emDisplay(26, italic: true))
    }

    // Титули з міксом ваг/шрифтів — як розмітка прототипу (em/strong).
    // Обчислювані, а не static let: привітання залежить від імені, і
    // картка має оновитись, щойно онбординг його запише
    private var cards: [HeroCard] { [
        HeroCard(id: 0, image: "SettingsHero1",
                 title: AnyView(greeting),
                 sub: "Embar - always there, always for you"),
        HeroCard(id: 1, image: "SettingsHero2",
                 title: AnyView(
                    (Text("YOUR").fontWeight(.medium)
                     + Text(" app, built for ").fontWeight(.light)
                     + Text("YOU").font(.emDisplay(26, italic: true)))),
                 sub: "Shaped to fit your workflow. If something feels off, let us know - we'll make it bend."),
        HeroCard(id: 2, image: "SettingsHero3",
                 title: AnyView(
                    (Text("Hidden ").fontWeight(.light)
                     + Text("Gems").font(.emDisplay(26, italic: true)))),
                 sub: "Get to know what interesting features Embar offers.",
                 subpage: .gems),
        HeroCard(id: 3, image: "SettingsHero4",
                 title: AnyView(
                    (Text("Join our ").fontWeight(.light)
                     + Text("Community").font(.emDisplay(26, italic: true)))),
                 sub: "Join the community of likeminded, creative, organized people.",
                 // Лінків спільноти ще немає - картка неактивна, у куті
                 // пігулка «Скоро» замість стрілки (фідбек 2026-09-19)
                 badge: "Скоро"),
    ] }

    var body: some View {
        GeometryReader { geo in
            // Трек: усі картки в ряд, зсув на -slide × width (прототип
            // heroTrack translateX)
            HStack(spacing: 0) {
                ForEach(cards) { card in
                    heroCard(card, width: geo.size.width)
                }
            }
            .offset(x: -CGFloat(slide) * geo.size.width)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.55), value: slide)
        }
        .frame(height: 210)
        .clipped()
        .overlay(alignment: .bottom) { dots }
        // Налаштування накривають шапку панелі: червона кнопка вікна
        // стоїть на фото картки - під нею мʼяке сяйво (SPEC §15.78,
        // 2026-09-27). Радіус - кута панелі, там і кнопка
        .overlay(alignment: .topLeading) {
            CloseButtonGlow(cornerRadius: PanelController.panelCornerRadius, buttons: 3)
        }
        .onReceive(timer) { _ in
            guard !paused else { return }
            slide = (slide + 1) % cards.count
        }
    }

    private func heroCard(_ card: HeroCard, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            card.title
                .font(.emUI(26, weight: .light))
                .foregroundStyle(EmbarColors.ink)
                .kerning(-0.6)
                .lineSpacing(2)
                // Імʼя в привітанні вводить користувач (кламп 30 символів),
                // тож довжину точно не знаємо. Заміряно бандленим Inter
                // у боксі 300pt:
                // «Hey, Solomiia Nechai» — 1 рядок, подвійне прізвище — 2,
                // найдовший фіксований титул (uk «ТВІЙ застосунок…») — теж 2.
                // Отже 2 рядки вміщає все наявне, а масштаб рятує від
                // третього — у картці на нього просто немає висоти
                // (210pt мінус паддінги і підзаголовок), і .clipped()
                // контейнера зрізав би хвіст
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(card.sub)
                .font(.emUI(12.5, weight: .light))
                .foregroundStyle(EmbarColors.ink2)
                .lineSpacing(4)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 28, leading: 30, bottom: 66, trailing: 30))
        .frame(width: width, height: 210, alignment: .bottomLeading)
        // Стрілка ↗ клікабельних карток (прототип .hero-card-arrow)
        .overlay(alignment: .topTrailing) {
            if card.subpage != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(EmbarColors.ink3)
                    .padding(.top, 32)
                    .padding(.trailing, 34)
            } else if let badge = card.badge {
                // Пігулка на місці стрілки: світла капсула на фото, як
                // активний сегмент перемикача матеріалу (біла капсула
                // з мʼякою тінню) - той самий стиль, не третій
                Text(badge)
                    .font(.emUI(11, weight: .medium))
                    .foregroundStyle(EmbarColors.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(EmbarColors.surface.opacity(0.9))
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1))
                    .padding(.top, 28)
                    .padding(.trailing, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let subpage = card.subpage { onOpenSubpage(subpage) }
        }
        .background(
            // Фото ЯК background Color.clear (паттерн ReaderBookCard):
            // greedy-розмір scaledToFill не роздуває картку
            Color.clear.background(
                photo(card.image)
                    .overlay(
                        // Прототип .hero-card::before: фото зверху →
                        // сильно білий низ під текст і перехід у sheet
                        LinearGradient(stops: [
                            .init(color: EmbarColors.surface.opacity(0), location: 0),
                            .init(color: EmbarColors.surface.opacity(0.10), location: 0.35),
                            .init(color: EmbarColors.surface.opacity(0.85), location: 0.70),
                            .init(color: EmbarColors.surface, location: 1.0),
                        ], startPoint: .top, endPoint: .bottom))
            )
            .clipped()
        )
    }

    /// Імена фото карток. Окремим списком, бо кешу потрібні лише файли,
    /// а самі картки стали обчислюваними (привітання залежить від імені)
    private static let photoNames = ["SettingsHero1", "SettingsHero2",
                                     "SettingsHero3", "SettingsHero4"]

    /// Фото декодуються ОДИН раз (урок ReaderBookCard: декод у body =
    /// мигання на кожен рендер)
    private static let photoCache: [String: NSImage] = {
        var cache: [String: NSImage] = [:]
        for name in photoNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "jpeg"),
               let img = NSImage(contentsOf: url) {
                cache[name] = img
            }
        }
        return cache
    }()

    @ViewBuilder private func photo(_ name: String) -> some View {
        if let nsImage = Self.photoCache[name] {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            EmbarColors.tint
        }
    }

    // Крапки (прототип .hero-dots: bottom 44, активна — смужка 18×5 r3)
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<cards.count, id: \.self) { i in
                Button {
                    slide = i
                } label: {
                    Capsule()
                        .fill(slide == i ? EmbarColors.ink : Color.black.opacity(0.18))
                        .frame(width: slide == i ? 18 : 5, height: 5)
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.3), value: slide)
            }
        }
        .padding(.bottom, 44)
    }
}
