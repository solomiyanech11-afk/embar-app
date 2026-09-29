//
//  SettingsSheetContent.swift
//  Embar
//
//  Вміст sheet налаштувань (прототип .settings-sheet): сегмент теми
//  (disabled — dark mode ще не існує, M6), сітка кастомізації (мова
//  disabled до локалізації; палітра — живий dropdown), далі Доступ і
//  фідбек (кроки 5–7). Fonts-картку прототипу НЕ показуємо: вона міняє
//  шрифт ВСЬОГО застосунку, а дизайн-система фіксує Inter (SPEC «Settings»).
//

import SwiftUI
import Carbon.HIToolbox

struct SettingsSheetContent: View {
    /// Обрано мову, яка справді змінить інтерфейс → SettingsPanel показує
    /// питання про перезапуск (діалог має накрити всю панель, а цей вміст
    /// живе всередині ScrollView — скрим звідси не дотягнувся б)
    var onAskRestart: (AppLanguage) -> Void = { _ in }
    /// Відкрити сабсторінку (Hidden Gems) - рядок списку, а не картка
    /// каруселі: карусель треба гортати, і трюки в ній не знаходили
    var onOpenSubpage: (SettingsSubpage.Kind) -> Void = { _ in }

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toasts: ToastCenter
    /// Джерело правди вибору мови живе в SettingsPanel: рішення ухвалює
    /// ЙОГО діалог перезапуску, і локальний @State тут відставав би -
    /// картка показувала стару мову, доки налаштування не перевідкриють
    /// (P2.28)
    @Binding var selectedLanguage: AppLanguage
    @State private var paletteOpen = false
    @State private var languageOpen = false
    @State private var gemsStops = SettingsSheetContent.shuffledGemsStops()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            themeSegment
            panelSurfaceDots // фон панелі — кружечки під сегментом теми
            custGrid
            materialSection // без заголовка, під сіткою (фідбек 2026-07-19)
            embarProCard // покупка доступна з першого дня (SPEC §15.77д)
            hiddenGemsRow
            accessSection
            feedbackSection
        }
    }

    // MARK: - Embar Pro: вхід до пейвола з першого дня
    //
    // Та сама форма картки, що Hidden Gems (без сяйва - воно фішка
    // Gems); підзаголовок живе станом доступу. При активній місячній
    // підписці всередині зʼявляється другий рядок «Керувати підпискою»
    // (вимога Apple: шлях до керування простісінько з застосунку)

    @ObservedObject private var entitlements = EntitlementStore.shared

    /// Найважливіша кнопка застосунку - на екрані ОДИН акцент, і це
    /// вона (фідбек 2026-09-17): рамка-сяйво переїхала сюди з Hidden
    /// Gems. Хто вже заплатив, акценту не потребує - у pro картка
    /// звичайна
    private var proCardGlows: Bool { entitlements.access != .pro }

    /// Підзаголовок від стану доступу; множина «день/дні/днів» - той
    /// самий ключ каталогу, що в пігулці пейвола
    private var proSubtitle: Text {
        switch entitlements.access {
        case .trial(let days):
            return Text(String(
                localized: "Лишилось \(days) дн. пробного періоду",
                comment: "Пігулка в шапці пейвола; день/дні/днів у каталозі"))
        case .pro:
            return Text("Активовано. Дякуємо за підтримку!")
        case .readOnly, .open:
            return Text("Пробний період завершився")
        }
    }

    /// Сяйво по контуру - той самий прийом, що на краю екрана в
    /// онбордингу (EdgeGlowHint): та сама обводка кілька разів, кожна
    /// ширша, розмитіша й прозоріша, зверху - чітка лінія. Читається як
    /// світло, а не як смужка. Масштаб під картку, не під край екрана
    private static let proGlowLayers: [(width: CGFloat, blur: CGFloat, opacity: Double)] = [
        (7, 9, 0.45),
        (3.5, 4, 0.65),
        (1.2, 0, 1.0),
    ]

    private var proGlow: some View {
        ZStack {
            ForEach(Array(Self.proGlowLayers.enumerated()), id: \.offset) { _, layer in
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AngularGradient(gradient: Gradient(stops: gemsStops),
                                                  center: .center),
                                  lineWidth: layer.width)
                    .blur(radius: layer.blur)
                    .opacity(layer.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var embarProCard: some View {
        VStack(spacing: 0) {
            Button { PaywallWindowController.shared.show() } label: {
                HStack(spacing: 12) {
                    // Знак Embar - той самий, що в шапці пейвола: картка
                    // візуально звʼязана з екраном, який відкриває
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(EmbarColors.line, lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Embar Pro")
                            .font(.emUI(14, weight: .medium))
                            .foregroundStyle(EmbarColors.ink)
                        proSubtitle
                            .font(.emUI(11.5))
                            .foregroundStyle(EmbarColors.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EmbarColors.ink3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if entitlements.proIsSubscription {
                Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Керувати підпискою")
                                .font(.emUI(12.5, weight: .medium))
                                .foregroundStyle(EmbarColors.ink)
                            Text("Змінити або скасувати - в App Store")
                                .font(.emUI(11))
                                .foregroundStyle(EmbarColors.ink3)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(EmbarColors.ink3)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
        .overlay { if proCardGlows { proGlow } }
        .padding(.bottom, 14)
        .task { await animateGemsGlow() }
    }

    // MARK: - Hidden Gems: постійний рядок НА ПОЧАТКУ списку
    //
    // Раніше трюки жили лише картинкою в hero-каруселі: щоб дістатись,
    // треба було догортати карусель, і люди їх не бачили. Картка в
    // каруселі лишається - вона декоративна, - але вхід тепер тут,
    // першим рядком, без жодного гортання (фідбек 2026-08-11)

    private var hiddenGemsRow: some View {
        Button { onOpenSubpage(.gems) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Hidden Gems")
                        .font(.emUI(14, weight: .medium))
                        .foregroundStyle(EmbarColors.ink)
                    Text("Трюки, які легко не помітити")
                        .font(.emUI(11.5))
                        .foregroundStyle(EmbarColors.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EmbarColors.ink3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
            // Сяйво по контуру звідси переїхало на картку Embar Pro
            // (фідбек 2026-09-17: на екрані один акцент). Іконки тут
            // немає свідомо: емодзі як іконка - проти правила проєкту, а
            // окремий гліф поруч із назвою англійською виглядав
            // чужорідно (фідбек 2026-08-11)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
    }

    /// Стопи кутового градієнта обводки. Прийом той самий, що в сяйві на
    /// краю екрана: позиції ЩОПІВСЕКУНДИ перетасовуються і переїжджають
    /// анімацією - саме випадковий переїзд читається як живий рух
    private static func shuffledGemsStops() -> [Gradient.Stop] {
        [OnboardingDesign.coral, OnboardingDesign.glowMint,
         OnboardingDesign.coral, OnboardingDesign.glowMint]
            .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }

    private func animateGemsGlow() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.2)) {
                gemsStops = Self.shuffledGemsStops()
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    // MARK: - Фон панелі: 5 кружечків на всю ширину (фідбек 2026-07-19 —
    // картка з dropdown виглядала негарно). Коли зʼявиться темна тема,
    // тут стануть темні відповідники цих відтінків

    private var panelSurfaceDots: some View {
        // Маленькі кружечки, тонке кільце, без підпису (фідбек 2026-07-19)
        HStack(spacing: 0) {
            ForEach(PanelSurface.allCases, id: \.rawValue) { option in
                let selected = PanelSurface.current == option
                Button {
                    theme.panelSurfaceRaw = option.rawValue // миттєво (§7.2-A)
                } label: {
                    ZStack {
                        // Кільце вибору — зовні кружечка
                        Circle()
                            .strokeBorder(EmbarColors.ink,
                                          lineWidth: selected ? 1 : 0)
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(option.color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle()
                                .strokeBorder(Color.black.opacity(0.1)))
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.name)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Тема панелі · тест (переїхало зі stickies settings; тимчасово
    // до закриття Glass-теми — BACKLOG)

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                materialButton("Звичайна", .opaque)
                // Скло й Левітація вимкнені (2026-08-11): працюють погано.
                // Той самий шлях, що в решти незробленого - повний
                // контраст і тост «скоро», без вимитих disabled-станів
                materialButton("Скло", .glass, soon: String(localized: "Скло"))
                materialButton("Левітація", .levitation, soon: String(localized: "Левітація"))
            }
            .padding(3)
            .background(Capsule().fill(EmbarColors.tint))
            if theme.materialTheme == .glass {
                HStack(spacing: 10) {
                    Slider(value: $theme.glassOpacity, in: 0...1)
                    Text("\(Int(theme.glassOpacity * 100))%")
                        .font(.emUI(11))
                        .monospacedDigit()
                        .foregroundStyle(EmbarColors.ink3)
                        .frame(width: 36, alignment: .trailing)
                }
                Text("Непрозорість «молока» панелі")
                    .font(.emUI(11)).italic().foregroundStyle(EmbarColors.ink3)
            }
        }
        .padding(.bottom, 28)
    }

    private func materialButton(_ label: LocalizedStringKey, _ value: MaterialTheme,
                                soon: String? = nil) -> some View {
        let active = theme.materialTheme == value
        return Button {
            if let soon {
                // Той самий ключ «%@ - скоро», що в решти незробленого
                toasts.showMini("\(soon) - скоро")
            } else {
                theme.materialTheme = value // перемикання теми — миттєве (§7.2-A)
            }
        } label: {
            Text(label)
                .font(.emUI(12.5, weight: active ? .medium : .regular))
                .foregroundStyle(active ? EmbarColors.ink : EmbarColors.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule().fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Фідбек (прототип «Ваш відгук нам важливий») — чесно працює
    // через mailto: лист-чернетка; бекенда немає, жодних запитів у мережу
    // з програми (B2 тест-плану) — обидві кнопки лише віддають URL системі

    /// Канали фідбеку (B2): адреса підтримки (не особиста) і зовнішня
    /// сторінка в браузері
    private enum FeedbackChannel {
        static let email = "support@embar.studio"
        static let subject = "Embar feedback"
        /// ⚠️ Заглушка: справжній URL дасть Mia (B2) — замінити ЛИШЕ цю
        /// константу, кнопка вже підключена
        static let browserURL = URL(string: "https://embar.studio/feedback")!
    }

    @State private var feedbackText = ""

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Ваш відгук нам важливий")
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $feedbackText)
                    .font(.emUI(13))
                    .foregroundStyle(EmbarColors.ink)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .frame(minHeight: 90)
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 40))
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(EmbarColors.ink, lineWidth: 1.5))
                    .overlay(alignment: .topLeading) {
                        if feedbackText.isEmpty {
                            Text("Будемо дуже вдячні за будь-який коментар або пропозицію для покращення.")
                                .font(.emUI(13))
                                .foregroundStyle(EmbarColors.ink3)
                                .padding(.top, 10).padding(.leading, 17)
                                .allowsHitTesting(false)
                        }
                    }
                Button(action: sendFeedback) {
                    Circle().fill(EmbarColors.ink)
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white))
                }
                .buttonStyle(.plain)
                .padding(9)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            }
            // Другий канал (B2): сторінка в браузері. Тихий рядок-посилання
            // під полем; URL — константа-заглушка FeedbackChannel.browserURL
            Button {
                NSWorkspace.shared.open(FeedbackChannel.browserURL)
            } label: {
                Text("Або лишіть відгук у браузері ›")
                    .font(.emUI(12))
                    .foregroundStyle(EmbarColors.ink3)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.leading, 4)
        }
        .padding(.bottom, 8)
    }

    /// mailto — чернетка в поштовому клієнті: відгук людини + технічний
    /// рядок із версією програми і macOS (B2; діагностиці це потрібно,
    /// а руками цього ніхто не напише)
    private func sendFeedback() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let bodyText = feedbackText + "\n\n" + "Embar \(version) (\(build)) · macOS \(os)"
        // ❗ Не голий .urlQueryAllowed: він пропускає & і + — амперсанд у
        // тексті відгуку зрізав би решту тіла як «наступний параметр»,
        // а + деякі клієнти читають як пробіл
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
        let body = bodyText.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        if let url = URL(string:
            "mailto:\(FeedbackChannel.email)?subject=Embar%20feedback&body=\(body)") {
            NSWorkspace.shared.open(url)
            feedbackText = ""
        }
    }

    // MARK: - Доступ (прототип .settings-section «Доступ»)

    @AppStorage("edgeHoverEnabled") private var edgeHoverEnabled = true
    /// Тижнева смужка внизу панелі (H2: Home сховано, тиждень лишився)
    @AppStorage("showWeekStrip") private var showWeekStrip = true
    @AppStorage(HotkeyManager.enabledKey) private var hotkeyEnabled = true
    @AppStorage(HotkeyManager.displayKey) private var hotkeyDisplay = "⌥E"
    @State private var recordingHotkey = false
    @State private var keyMonitor: Any?

    private var accessSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Доступ")
            VStack(spacing: 0) {
                hotkeyRow
                Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
                // Виклик при наведенні — живий toggle (PanelController
                // читає ключ у edge-тригері). Великий 70×26, як .qn-toggle
                // прототипу — в один розмір із пігулкою шортката
                accessRow(label: "Виклик при наведенні",
                          desc: "Панель з'являється, коли курсор біля краю екрана") {
                    BigToggle(isOn: $edgeHoverEnabled)
                }
                Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
                accessRow(label: "Показувати тиждень",
                          desc: "Смужка з днями тижня внизу панелі") {
                    BigToggle(isOn: $showWeekStrip)
                }
                Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
                // Розміщення — однорядковий (прототип); панель поки тільки
                // справа → клік каже «скоро»
                HStack {
                    Text("Розміщення закладки")
                        .font(.emUI(14))
                        .foregroundStyle(EmbarColors.ink)
                    Spacer()
                    Button {
                        toasts.showMini("Панель зліва - скоро")
                    } label: {
                        HStack(spacing: 5) {
                            Text("Справа").font(.emUI(13, weight: .medium))
                            Text("▾").font(.system(size: 10))
                                .foregroundStyle(EmbarColors.ink3)
                        }
                        .foregroundStyle(EmbarColors.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
                replayOnboardingRow
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
        }
        .padding(.bottom, 28)
    }

    /// Знайомство наново - ОДРАЗУ, не «при наступному запуску». Прибраний
    /// на користь Hidden Gems рядок повернуто (ревʼю 2026-08-12 №7):
    /// без нього людина, що закрила знайомство хрестиком, втрачала
    /// навчання жесту назавжди - прапорець ставиться і при пропуску.
    /// Навчальний контент НЕ пересіюється: у сіячів власні прапорці
    private var replayOnboardingRow: some View {
        accessRow(label: "Показати знайомство знову",
                  desc: "Три коротких кроки - як викликати панель і з чого почати") {
            Button {
                OnboardingStore.replay()
                let panel = AppDelegate.current?.panelController
                OnboardingWindowController.shared.start(panelController: panel) {
                    panel?.show(reason: .programmatic)
                }
            } label: {
                Text("Показати")
                    .font(.emUI(12.5, weight: .medium))
                    .foregroundStyle(EmbarColors.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(EmbarColors.tint))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        // .textCase, а не .uppercased(): регістр — уже до перекладу (i18n)
        Text(text)
            .textCase(.uppercase)
            .font(.emUI(11, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(EmbarColors.ink3)
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EmbarColors.line).frame(height: 1)
            }
            .padding(.bottom, 14)
    }

    // MARK: - Шорткат: toggle-пігулка з комбінацією (прототип
    // .toggle-shortcut) + запис своєї комбінації

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Виклик через шорткат")
                    .font(.emUI(14))
                    .foregroundStyle(EmbarColors.ink)
                Spacer()
                shortcutPill
            }
            Text(recordingHotkey
                 ? "Натисни нову комбінацію з ⌘/⌥/⌃ (Esc - скасувати)"
                 : "Швидкий виклик панелі з клавіатури")
                .font(.emUI(11.5))
                .foregroundStyle(recordingHotkey ? EmbarColors.ink2 : EmbarColors.ink3)
            if hotkeyEnabled {
                Button {
                    recordingHotkey ? endRecording() : beginRecording()
                } label: {
                    Text(recordingHotkey ? "слухаю…" : "змінити комбінацію")
                        .font(.emUI(11, weight: .medium))
                        .foregroundStyle(EmbarColors.ink2)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onDisappear { endRecording() }
        .onChange(of: hotkeyEnabled) { _, _ in
            if !hotkeyEnabled { endRecording() }
            NotificationCenter.default.post(name: .embarHotkeyChanged, object: nil)
        }
    }

    /// Пігулка 70×26 як у прототипі: ON — чорна з комбінацією і кулькою
    /// справа; OFF — сіра, кулька зліва
    private var shortcutPill: some View {
        Button {
            hotkeyEnabled.toggle() // toggle — анімована поверхня (§7.2-A)
        } label: {
            ZStack(alignment: hotkeyEnabled ? .trailing : .leading) {
                Capsule()
                    .fill(hotkeyEnabled ? EmbarColors.ink : Color.black.opacity(0.15))
                if hotkeyEnabled {
                    Text(hotkeyDisplay)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .padding(3)
            }
            .frame(width: 70, height: 26)
            .animation(.spring(response: 0.22, dampingFraction: 0.8),
                       value: hotkeyEnabled)
        }
        .buttonStyle(.plain)
    }

    private func beginRecording() {
        recordingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc — скасувати
                endRecording()
                return nil
            }
            let flags = event.modifierFlags
                .intersection([.command, .option, .control, .shift])
            // Хоч один «сильний» модифікатор — інакше конфлікт зі звичайним
            // набором тексту
            guard flags.contains(.command) || flags.contains(.option)
                    || flags.contains(.control) else { return nil }
            var carbon: UInt32 = 0
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            if flags.contains(.option) { carbon |= UInt32(optionKey) }
            if flags.contains(.control) { carbon |= UInt32(controlKey) }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

            let d = EmbarDefaults.store
            d.set(Int(event.keyCode), forKey: HotkeyManager.keyCodeKey)
            d.set(Int(carbon), forKey: HotkeyManager.modifiersKey)
            hotkeyDisplay = Self.symbols(for: flags) + Self.keyLabel(for: event)
            NotificationCenter.default.post(name: .embarHotkeyChanged, object: nil)
            endRecording()
            return nil // подія проковтнута — не летить у поля панелі
        }
    }

    private func endRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingHotkey = false
    }

    private static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    /// Великий тумблер 70×26 (прототип .qn-toggle) — та сама геометрія,
    /// що пігулка шортката; кулька 20, слайд-пружина 0.22
    private struct BigToggle: View {
        @Binding var isOn: Bool

        var body: some View {
            Button {
                isOn.toggle() // toggle — анімована поверхня (§7.2-A)
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? EmbarColors.ink : Color.black.opacity(0.15))
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .padding(3)
                }
                .frame(width: 70, height: 26)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isOn)
            }
            .buttonStyle(.plain)
        }
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }

    private func accessRow(label: LocalizedStringKey, desc: LocalizedStringKey,
                           @ViewBuilder trailing: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.emUI(14))
                    .foregroundStyle(EmbarColors.ink)
                Spacer()
                trailing()
            }
            Text(desc)
                .font(.emUI(11.5))
                .foregroundStyle(EmbarColors.ink3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Сегмент теми (прототип .theme-segment). Вигляд 1:1 з
    // прототипом (повний контраст); dark mode ще не існує — клік каже
    // «скоро» тостом (фідбек 2026-07-19: без «вимитих» disabled-станів)

    private var themeSegment: some View {
        EmbarSegment(
            options: [
                .init(id: "light", label: "Light", icon: "sun.max"),
                .init(id: "system", label: "System", icon: "circle.lefthalf.filled"),
                .init(id: "dark", label: "Dark", icon: "moon"),
            ],
            selection: "system"
        ) { _ in
            toasts.showMini("Темна тема - скоро")
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Сітка кастомізації (прототип .cust-grid)

    // Сітка прототипу: ЛІВА колонка — мова над палітрою; права колонка
    /// Що показує картка: сам вибір («Як у системі» лишається собою, а не
    /// підмінюється назвою мови — інакше не видно, що override знято)
    private var currentLanguageName: String {
        switch selectedLanguage {
        case .system: String(localized: "Як у системі",
                             comment: "Пункт вибору мови — без власного override")
        case .uk: "Українська"
        case .en: "English"
        }
    }

    // MARK: - Dropdown мови (SPEC §6.4). Вигляд — як у палітри:
    // назва + ✓ на обраному, той самий popover і ті самі відступи

    private var languageDropdown: some View {
        VStack(spacing: 3) {
            ForEach(AppLanguage.allCases) { language in
                let selected = selectedLanguage == language
                Button { pick(language) } label: {
                    HStack(spacing: 10) {
                        Text(language.title)
                            .font(.emUI(12, weight: .medium))
                            .foregroundStyle(EmbarColors.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if selected {
                            Text("✓")
                                .font(.emUI(12))
                                // Галочка = БРЕНД (див. близнюка нижче)
                                .foregroundStyle(EmbarColors.brandRed)
                        }
                    }
                    .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.black.opacity(0.04) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 190)
    }

    private func pick(_ language: AppLanguage) {
        languageOpen = false
        guard language != selectedLanguage else { return }
        // Питаємо ПЕРЕД записом: поки користувач не вирішив, нічого не
        // чіпаємо — інакше «Пізніше» лишило б застосунок у стані, де
        // картка каже одне, а інтерфейс показує інше
        if LanguageStore.changesLanguage(to: language) {
            onAskRestart(language)
        } else {
            // Вибір нічого не змінює (напр. система вже українська) —
            // просто запамʼятовуємо, перезапуск ні до чого
            LanguageStore.selected = language
            selectedLanguage = language
        }
    }

    // (місце fonts-картки, яку не показуємо — SPEC §6) — фон панелі
    private var custGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            // Spacer між клітинками замість фіксованого проміжку: ліва
            // колонка тягнеться на висоту правої, і низ «палітри» сходиться
            // з низом «fonts» сам. З числом 16 палітра вилазила за край
            // картки шрифтів (фідбек 2026-08-11)
            VStack(alignment: .leading, spacing: 0) {
                // Мова — живий dropdown (SPEC §6.4). Вибір застосовується
                // після перезапуску, тож питаємо про нього діалогом
                custCell(label: "мова") {
                    Button { languageOpen.toggle() } label: {
                        custCard {
                            Text(currentLanguageName)
                                .font(.emUI(14, weight: .medium))
                                .foregroundStyle(EmbarColors.ink)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $languageOpen, arrowEdge: .bottom) {
                        languageDropdown
                    }
                }
                Spacer(minLength: 10)
                // Палітра — живий dropdown зі свотчами
                custCell(label: "палітра") {
                    Button { paletteOpen.toggle() } label: {
                        custCard {
                            HStack(spacing: 3) {
                                ForEach(0..<theme.current.sticky.count, id: \.self) { i in
                                    Circle()
                                        .fill(theme.current.sticky[i])
                                        .frame(width: 10, height: 10)
                                        .overlay(Circle()
                                            .strokeBorder(Color.black.opacity(0.07)))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $paletteOpen, arrowEdge: .bottom) {
                        paletteDropdown
                    }
                }
            }
            .frame(maxHeight: .infinity)
            // Fonts-картка (прототип .fonts-card): 2×2 «Aa», Inter активний.
            // Зміна шрифту застосунку ще не реалізована — клік каже «скоро»
            custCell(label: "fonts") {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        fontMini(.emUI(18, weight: .medium), active: true)
                        fontMini(.custom("Georgia", size: 18))
                    }
                    HStack(spacing: 6) {
                        fontMini(.emDisplay(18, italic: true))
                        fontMini(.system(size: 15, design: .monospaced))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
            }
        }
        .padding(.bottom, 16)
    }

    /// Міні-кнопка шрифту (прототип .font-mini-opt): tint-квадрат r13,
    /// активна — біла з чорною рамкою 1.5
    private func fontMini(_ font: Font, active: Bool = false) -> some View {
        Button {
            if !active { toasts.showMini("Шрифт застосунку - скоро") }
        } label: {
            Text("Aa")
                .font(font)
                .foregroundStyle(EmbarColors.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 13)
                    .fill(active ? Color.white : EmbarColors.tint))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(EmbarColors.ink, lineWidth: active ? 1.5 : 0))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }


    private func custCell(label: LocalizedStringKey,
                          @ViewBuilder card: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            card()
            Text(label)
                .font(.emUI(11))
                .foregroundStyle(EmbarColors.ink3)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func custCard(@ViewBuilder value: () -> some View) -> some View {
        HStack {
            value()
            Spacer(minLength: 8)
            Text("▾")
                .font(.system(size: 11))
                .foregroundStyle(EmbarColors.ink3)
        }
        .frame(minHeight: 20)
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Dropdown палітр (прототип #paletteDropdown: смужка 5 кольорів
    // + назва + ✓; вибір застосовується миттєво, §7.2-A)

    private var paletteDropdown: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(Palette.all) { palette in
                    let selected = theme.current.slug == palette.slug
                    Button {
                        theme.select(palette)
                        paletteOpen = false
                    } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: 0) {
                                ForEach(0..<palette.sticky.count, id: \.self) { i in
                                    palette.sticky[i]
                                }
                            }
                            .frame(width: 62, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(palette.name)
                                .font(.emUI(12, weight: .medium))
                                .foregroundStyle(EmbarColors.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if selected {
                                Text("✓")
                                    .font(.emUI(12))
                                    // Галочка = БРЕНД (ревізія 2026-08-17).
                                    // Був прибитий вохристий #c97a3a —
                                    // акцент однієї палітри (Cream) у ролі
                                    // загального UI-елемента: у решті 14
                                    // палітр він читався випадковою
                                    // помаранчевою плямою
                                    .foregroundStyle(EmbarColors.brandRed)
                            }
                        }
                        .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 8))
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.black.opacity(0.04) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .frame(width: 190, height: 300)
    }
}
