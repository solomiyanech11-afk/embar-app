//
//  SettingsSubpage.swift
//  Embar
//
//  Сабсторінки hero-карток (прототип .settings-subpage-overlay):
//  Hidden Gems (поради) і Community (лінки спільноти). Оверлей із
//  затемненням+блюром поверх Settings, центрована картка r20 зі
//  sticky-шапкою (back + Fraunces-титул) і fade під нею.
//  Лінки спільноти ще не існують — клік каже «скоро» тостом.
//

import SwiftUI

struct SettingsSubpage: View {
    enum Kind { case gems, community }

    @EnvironmentObject private var toasts: ToastCenter
    let kind: Kind
    var onClose: () -> Void

    var body: some View {
        ZStack {
            // Затемнення + блюр (прототип rgba .32 + blur 8); клік — закрити
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.32)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .overlay {
            card
                .padding(.horizontal, 20)
                .padding(.vertical, 36)
        }
    }

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if kind == .gems { gemsBody } else { communityBody }
            }
            .padding(.horizontal, 22)
            .padding(.top, 60) // під sticky-шапкою
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
        // Sticky-шапка з fade — контент тане, не зрізається (правило проєкту)
        .overlay(alignment: .top) { header }
        .background(RoundedRectangle(cornerRadius: 20).fill(EmbarColors.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 7)
        .onTapGesture {} // клік по картці не закриває
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Circle()
                    .fill(EmbarColors.tint)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EmbarColors.ink))
            }
            .buttonStyle(.plain)
            Text(kind == .gems ? "Hidden Gems" : "Community")
                .font(.emDisplay(20, italic: true))
                .foregroundStyle(EmbarColors.ink)
            Spacer()
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 12, trailing: 18))
        .background(
            LinearGradient(stops: [
                .init(color: EmbarColors.surface, location: 0),
                .init(color: EmbarColors.surface, location: 0.7),
                .init(color: EmbarColors.surface.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .padding(.bottom, -14)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Hidden Gems
    //
    // Пʼять секцій за поверхнями застосунку, довгий скрол без згортань
    // (2026-08-11). Кожне твердження звірене з кодом - список звірки й
    // тексти парами лежать у docs/HIDDEN-GEMS-COPY.md.
    //
    // Рядки щільніші за колишні: заголовок 13/500, опис 11.5 muted,
    // вертикальний padding 8 замість 12 - мета вмістити всі пʼять
    // секцій у два-три скроли.

    private var gemsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionH3("Загальне", first: true)
            row("lock", "Замочок у хедері",
                "Поки закритий, панель не ховається, коли ведеш мишу геть.")
            row("command", "Свій шорткат виклику",
                "⌥E можна змінити: Налаштування → Доступ → «змінити комбінацію».")
            row("arrow.left.and.right", "Панель тягнеться за лівий край",
                "Візьми край і потягни. Ширину застосунок запамʼятає до наступного разу.")
            row("arrow.uturn.backward", "Скасувати видалене",
                "У блокноті Рідера - ⌘Z, до 30 кроків. Деінде - кнопка «Скасувати» в тості, поки він не зник.")

            sectionH3("Стіки")
            row("doc.text", "Стік стає нотаткою",
                "Відкрий стік і натисни документ у панелі під карткою. Текст переїде, стік залишиться.")
            row("bell", "Дедлайн сам нагадає",
                "У дедлайні є «Нагадати»: у момент, за 5 чи 30 хвилин, за годину або за день.")
            row("face.smiling", "Емоджі-теги",
                "Причепи смайлик у відкритому стіку, і в налаштуваннях стіни зʼявиться фільтр по ньому.")
            row("archivebox", "Виконані йдуть в архів самі",
                "Строк - у загальних налаштуваннях стіків: тиждень, місяць або три.")
            row("paintpalette", "Кольори стіків",
                "Різнокольорові чи один колір на стіну - перемикач у загальних налаштуваннях стіків, там же архів і показ виконаних.")

            sectionH3("Нотатки")
            row("link", "Напиши [[ і обери нотатку",
                "Зʼявиться звʼязок, а внизу тієї нотатки - хто її згадує.")
            row("circle.lefthalf.filled", "Нотатці можна дати колір",
                "Акцент картки в кружечках зверху, колір тексту й маркер - у тулбарі.")
            row("slider.vertical.3", "Шестерня всередині нотатки",
                "Шрифт, розмір, інтервал і фокус-режим - окремо для кожної нотатки.")

            sectionH3("Рідер")
            row("photo", "Обкладинка блокнота",
                "Фото зверху блокнота, а під ним - посилання на джерело, до якого ведеш нотатки.")
            row("bookmark", "Thread групує записи",
                "Увімкни - і все нове лягає під його заголовок. Тап по назві продовжує тему пізніше, подвійний тап по трикутнику згортає всі теми блокнота.")
            row("mic", "Олівець, камера, мікрофон",
                "Олівець фарбує виділене, камера чіпляє фото до запису, мікрофон пише голосову думку.")
            row("list.bullet", "Більше типів записів",
                "Думка й Цитата є завжди; Питання та Інсайт вмикаються в налаштуваннях Рідера.")
            row("doc.badge.plus", "Запис стає нотаткою",
                "Іконка документа на записі: у нову нотатку або в одну з останніх.")
            row("number", "#теги в тексті запису",
                "Стають кольоровими пігулками, і по них можна фільтрувати стрічку.")

            // Home сховано з v1 (HomeFeature) — ґеми повернуться разом
            // з екраном
            if HomeFeature.enabled {
                sectionH3("Home")
                row("calendar", "Тиждень угорі перемикає день",
                    "Три дні назад і три вперед. Минуле лише читається, майбутнє можна планувати.")
                row("hand.draw", "Потягни по таймлайну",
                    "Так створюється подія. За її край міняється тривалість, за середину - час.")
                row("checklist", "Тудушка редагується тапом",
                    "Тап по тексту - і можна переписати. Теки перемикаються крапками над карткою.")
            }
        }
    }

    // MARK: - Community

    private var communityBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Спільнота людей які цінують тишу, ритуал, і добре записану думку. Ділимось трюками, новими ідеями, цікавими use-case'ами.")
                .font(.emUI(13))
                .foregroundStyle(EmbarColors.ink2)
                .lineSpacing(4)
                .padding(.bottom, 16)
            sectionH3("Долучайся")
            linkRow("bubble.left", "Discord", "Щоденні обговорення, питання, ідеї.")
            linkRow("camera", "Instagram", "Натхнення, скріни, маленькі історії.")
            linkRow("envelope", "Newsletter", "Раз на місяць - головне, без шуму.")
        }
    }

    // MARK: - Будівельні блоки (прототип .subpage-row / h3)

    private func sectionH3(_ text: LocalizedStringKey, first: Bool = false) -> some View {
        // .textCase, а не .uppercased(): регістр — уже до перекладу (i18n)
        Text(text)
            .textCase(.uppercase)
            .font(.emUI(11, weight: .medium))
            .tracking(1.3)
            .foregroundStyle(EmbarColors.ink3)
            .padding(.top, first ? 0 : 18)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EmbarColors.line).frame(height: 1)
            }
            .padding(.bottom, 6)
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ desc: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(EmbarColors.ink)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.emUI(13, weight: .medium))
                    .foregroundStyle(EmbarColors.ink)
                Text(desc)
                    .font(.emUI(11.5))
                    .foregroundStyle(EmbarColors.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EmbarColors.line).frame(height: 1)
        }
    }

    /// Лінк-ряд із шевроном; реальних лінків ще немає — «скоро».
    ///
    /// `title` тут саме LocalizedStringResource, а не LocalizedStringKey:
    /// назва підставляється в тост «%@ - скоро», а LocalizedStringKey
    /// в інтерполяцію віддає СВІЙ ДЕБАГ-ОПИС, не текст — у тості
    /// зʼявилось би «LocalizedStringKey(key: "Discord"…) — скоро»
    /// (спіймано чистим білдом 2026-08-07)
    private func linkRow(_ icon: String, _ title: LocalizedStringResource,
                         _ desc: LocalizedStringKey) -> some View {
        Button {
            toasts.showMini("\(String(localized: title)) - скоро")
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(EmbarColors.ink)
                    .frame(width: 22, height: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.emUI(14, weight: .medium))
                        .foregroundStyle(EmbarColors.ink)
                    Text(desc)
                        .font(.emUI(12))
                        .foregroundStyle(EmbarColors.ink3)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.emUI(14))
                    .foregroundStyle(EmbarColors.ink4)
                    .padding(.top, 2)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EmbarColors.line).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
