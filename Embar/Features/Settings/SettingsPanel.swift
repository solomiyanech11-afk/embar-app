//
//  SettingsPanel.swift
//  Embar
//
//  Загальні налаштування (прототип .settings-panel): повнопанельний
//  оверлей slide-from-right 0.32s, зверху hero-карусель, нижче білий
//  sheet «App Settings» — сегмент теми, сітка кастомізації, Доступ,
//  фідбек. Що працює / що disabled — SPEC «Settings».
//

import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    var onClose: () -> Void
    /// Відкрита сабсторінка hero-картки (Hidden Gems / Community)
    @State private var subpage: SettingsSubpage.Kind?
    /// Обрана мова чекає на перезапуск (SPEC §6.4)
    @State private var pendingLanguage: AppLanguage?
    /// Поточний вибір мови - джерело правди для картки в sheet (P2.28):
    /// рішення діалогу нижче мусить оновити і її, інакше картка показує
    /// стару мову до перевідкриття налаштувань
    @State private var selectedLanguage = LanguageStore.selected

    var body: some View {
        VStack(spacing: 0) {
            SettingsHero(paused: subpage != nil) { subpage = $0 }
            sheet
        }
        // Під питанням про перезапуск - світлий блюр як при розгорнутому
        // стіку. До .embarOverlaySurface, щоб фон лишався суцільним
        .dialogDimmed(pendingLanguage != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .embarOverlaySurface()
        // Сабсторінка — оверлей із затемненням, scale+fade 0.28s (прототип)
        .overlay {
            if let subpage {
                SettingsSubpage(kind: subpage) { self.subpage = nil }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.28), value: subpage != nil)
        // Питання про перезапуск — той самий EmbarDialog, що й видалення
        .overlay {
            if let language = pendingLanguage {
                EmbarDialog(title: "Мова зміниться після перезапуску",
                            onCancel: { pendingLanguage = nil }) {
                    ConfirmChoicePill(label: "Перезапустити зараз",
                                      fill: EmbarColors.ink, text: .white) {
                        LanguageStore.selected = language
                        selectedLanguage = language
                        pendingLanguage = nil
                        LanguageStore.relaunch()
                    }
                    ConfirmChoicePill(label: "Пізніше") {
                        // Вибір усе одно запамʼятовуємо — застосується
                        // при наступному запуску
                        LanguageStore.selected = language
                        selectedLanguage = language
                        pendingLanguage = nil
                    }
                }
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2),
                   value: pendingLanguage != nil)
    }

    // MARK: - Sheet (прототип .settings-sheet: біла поверхня НАД hero,
    // заокруглена шапка з тінню, -22px нахлест)

    private var sheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSheetContent(onAskRestart: { pendingLanguage = $0 },
                                     onOpenSubpage: { subpage = $0 },
                                     selectedLanguage: $selectedLanguage)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64) // місце під sticky-шапкою
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        // Sticky-шапка НАД скролом: контент розчиняється у fade-градієнті,
        // а не зрізається об полоску (прототип .sheet-header; правило
        // «скрол завжди затуманюється», фідбек 2026-07-19)
        .overlay(alignment: .top) { sheetHeader }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24,
                                          topTrailingRadius: 24))
        .background(
            // r24 зверху, тінь вгору — sheet «нависає» над фото
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(EmbarColors.surface)
                .shadow(color: .black.opacity(0.12), radius: 12, y: -5)
        )
        .padding(.top, -22) // нахлест на hero (прототип margin-top: -22px)
    }

    private var sheetHeader: some View {
        ZStack {
            Text("App Settings")
                .font(.emUI(16, weight: .medium))
                .foregroundStyle(EmbarColors.ink)
            HStack {
                Button(action: onClose) {
                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                        .overlay(Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EmbarColors.ink))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(
            // Solid зверху → прозоро знизу: текст, що заїжджає під шапку,
            // плавно тане (прототип linear-gradient 0/60/100%)
            LinearGradient(stops: [
                .init(color: EmbarColors.surface, location: 0),
                .init(color: EmbarColors.surface, location: 0.6),
                .init(color: EmbarColors.surface.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .padding(.bottom, -18) // fade-зона тягнеться нижче шапки
            .allowsHitTesting(false)
        )
    }
}
