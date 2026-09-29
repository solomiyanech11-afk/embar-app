//
//  OnboardingView.swift
//  Embar
//
//  Знайомство при першому запуску — варіант «Проявник» із хендофу
//  дизайну (docs/design_handoff_embar_onboarding). Чотири такти в одному
//  вікні 660×440:
//
//  1. ПРОЯВЛЕННЯ — спершу лише чіткий знак Embar. Через 900 мс скляна
//     шторка сама наповзає до половини, проявляючи вітання й тагляйн;
//     далі людина ВЛАСНОЮ РУКОЮ дотягує ричаг вправо, і скло росте за
//     рукою до кінця. Перший дотик до Embar — дія, а не читання.
//  2. ІМʼЯ — «Як до тебе звертатися?» і пігулка з кнопкою всередині.
//  3. ЖЕСТ — «Панель поруч». Тут ми свідомо відійшли від прототипу:
//     замість іграшкової панельки в кутку вікна вмикаємо СПРАВЖНЮ
//     підказку-світіння на краю екрана і чекаємо справжнього жесту.
//  4. СТІКИ — фінальна картка; існує лише якщо туторіал реально сіявся.
//
//  Скляну шторку малює САМА вʼюха: розмита копія тла під маскою.
//  Нативний NSVisualEffectView пробували окремим шаром — на повній силі
//  він змішував мʼяту з розмитим знаком у брудний відтінок, а
//  напівпрозорий переставав бути склом узагалі (фідбек 2026-08-09).
//
//  Тексти на всіх тактах вирівняні ПО ЦЕНТРУ (фідбек 2026-08-09).
//  Пропуск можливий на будь-якому такті — хрестик у нижньому куті.
//

import SwiftUI

// MARK: - Тло вікна (шар [0]: мʼята + знак)

/// Живе під склом окремою hosting-вʼюхою, тому винесено з OnboardingView
struct OnboardingBackdropView: View {
    var body: some View {
        ZStack {
            OnboardingDesign.bg
            Image("logo-mark")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 300, height: 300)
                .foregroundStyle(OnboardingDesign.coral)
        }
        .frame(width: OnboardingDesign.width, height: OnboardingDesign.height)
    }
}

// MARK: - Контент (шар [2])

struct OnboardingView: View {
    private enum Stage {
        case reveal
        case name
        case gesture
        case stickies
    }

    @State private var stage: Stage = .reveal
    /// Ширина скляної шторки, 0…1. Значення жене в AppKit-шар скла
    @State private var progress: CGFloat = 0
    @State private var introTask: Task<Void, Never>?

    /// Reduced motion: без авто-інтро і без пружних відкатів (хендоф)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var D: OnboardingDesign.Type { OnboardingDesign.self }

    var body: some View {
        ZStack {
            OnboardingBackdropView()
            glassCurtain
            stageContent
            // Пропуск - червона кнопка вікна зліва вгорі (утилітарна
            // смужка, SPEC §15.78): OnboardingWindowController.finish()
        }
        .frame(width: D.width, height: D.height)
        .clipShape(RoundedRectangle(cornerRadius: D.windowRadius))
        // Сяйво під червоною кнопкою вікна: кнопка стоїть на зображенні
        // (мʼята + знак), а не на кремовому тлі (SPEC §15.78, 2026-09-27)
        .overlay(alignment: .topLeading) {
            CloseButtonGlow(cornerRadius: D.windowRadius)
        }
        .overlay(
            RoundedRectangle(cornerRadius: D.windowRadius)
                .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
        )
        .onAppear(perform: startIntro)
        .onDisappear { introTask?.cancel() }
    }

    private var curtainWidth: CGFloat {
        max(0, (D.width - D.inset * 2) * progress)
    }

    // MARK: - Скляна шторка, що наповзає

    private var glassCurtain: some View {
        let w = curtainWidth
        let h = D.height - D.inset * 2
        let shape = RoundedRectangle(cornerRadius: D.glassRadius)
        return OnboardingBackdropView()
            .blur(radius: D.backdropBlur)
            .overlay(OnboardingDesign.glassTint)
            .frame(width: D.width, height: D.height)
            .mask(
                shape
                    .frame(width: w, height: h)
                    .position(x: D.inset + w / 2, y: D.height / 2)
            )
            .overlay(
                shape
                    .strokeBorder(OnboardingDesign.glassStroke, lineWidth: 1)
                    .frame(width: w, height: h)
                    .position(x: D.inset + w / 2, y: D.height / 2)
                    .opacity(progress > 0.02 ? 1 : 0)
            )
            .shadow(color: Color(hex: "#1B2A27").opacity(0.14), radius: 30, y: 12)
            .allowsHitTesting(false)
    }

    // MARK: - Вміст такту
    //
    // Переходи між тактами — мʼякий крос-фейд. Різке перемикання читалось
    // як смикання (фідбек 2026-08-09); правило руху §7.2-A дозволяє
    // анімацію там, де поверхня справді змінюється, а тут змінюється
    // весь екран знайомства

    @ViewBuilder
    private var stageContent: some View {
        ZStack {
            switch stage {
            case .reveal: revealStage
            case .name: nameStage
            case .gesture: gestureStage
            case .stickies: stickiesStage
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : OnboardingDesign.ease(0.45), value: stage)
    }

    /// Перехід такту — в одному місці, щоб анімація була всюди однакова
    private func go(to next: Stage) {
        withAnimation(reduceMotion ? nil : OnboardingDesign.ease(0.45)) {
            stage = next
        }
    }

    // MARK: - Такт 1: проявлення

    /// Тексти проявляються разом зі шторкою
    private var revealed: Bool { progress >= 0.5 }

    /// Ширина, у якій живуть тексти першого такту — половина вікна під
    /// шторкою; текст центрується саме в ній
    private var curtainHalf: CGFloat { (D.width - D.inset * 2) / 2 }

    private var revealStage: some View {
        ZStack(alignment: .topTrailing) {
            Text("Вітаю\nв Embar")
                .font(.emDisplay(46, weight: .light))
                .tracking(-0.03 * 46)
                .foregroundStyle(OnboardingDesign.ink)
                .multilineTextAlignment(.center)
                .fixedSize()
                .frame(width: curtainHalf)
                .position(x: D.inset + curtainHalf / 2, y: D.height * 0.42)
                .opacity(revealed ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: revealed)

            Text("Місце для збереження твоїх думок, перш ніж вони погаснуть.")
                .font(.emUI(12))
                .lineSpacing(3)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(OnboardingDesign.inkSoft)
                .frame(width: 200, alignment: .trailing)
                .padding(.top, 32)
                .padding(.trailing, 34)
                .opacity(revealed ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: revealed)

            if revealed { lever }
        }
        .frame(width: D.width, height: D.height, alignment: .topTrailing)
    }

    // MARK: - Ричаг «протягни, щоб продовжити»

    private static let trackWidth: CGFloat = 268
    private static let trackHeight: CGFloat = 56
    private static let knobSize: CGFloat = 44
    /// Скільки повзунок реально проїжджає
    private static var knobTravel: CGFloat { trackWidth - trackHeight }

    /// Позиція повзунка 0…1 — похідна від progress (0.5 → 1)
    private var knobProgress: CGFloat {
        max(0, min(1, (progress - 0.5) * 2))
    }

    @State private var leverVisible = false

    private var lever: some View {
        VStack(spacing: 10) {
            Text("протягни, щоб продовжити")
                .font(.emUI(12))
                .textCase(.uppercase)
                .tracking(0.12 * 12)
                .foregroundStyle(OnboardingDesign.inkSoft)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .overlay(Capsule().strokeBorder(OnboardingDesign.pillStroke, lineWidth: 1))

                Circle()
                    .fill(OnboardingDesign.coralFill)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .overlay(
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: OnboardingDesign.coral.opacity(0.35), radius: 11, y: 5)
                    .offset(x: 6 + knobProgress * Self.knobTravel)
            }
            .frame(width: Self.trackWidth, height: Self.trackHeight)
            .contentShape(Capsule())
            .gesture(leverDrag)
        }
        .frame(width: curtainHalf)
        .position(x: D.inset + curtainHalf / 2,
                  y: D.height - 34 - Self.trackHeight / 2 - 11)
        .opacity(leverVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5).delay(0.2), value: leverVisible)
        .onAppear { leverVisible = true }
    }

    private var leverDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // ❗ Після finishLever драг ще живий і далі шле onChanged
                // (reveal-вʼюха лишається в дереві на час крос-фейду) -
                // без guard-а кожен рух миші перезаписував progress і
                // шторка застрягала неповною (ревʼю №5)
                guard stage == .reveal else { return }
                // Курсор тримає повзунок за центр: віднімаємо пів-кнопки
                let p = (value.location.x - Self.knobSize / 2 - 6) / Self.knobTravel
                // Під час драгу — БЕЗ анімації: скло має йти рівно за рукою
                progress = 0.5 + max(0, min(1, p)) * 0.5
                if knobProgress > 0.94 { finishLever() }
            }
            .onEnded { _ in
                guard stage == .reveal else { return }
                if knobProgress > 0.94 {
                    finishLever()
                } else {
                    // Не дотягнув — шторка пружно повертається до половини
                    withAnimation(reduceMotion ? nil
                                  : OnboardingDesign.ease(OnboardingDesign.introDuration)) {
                        progress = 0.5
                    }
                }
            }
    }

    private func finishLever() {
        guard stage == .reveal else { return }
        // reduceMotion - як у startIntro й onEnded: файл обіцяє «без
        // пружних відкатів», і дотяг не виняток (ревʼю №10)
        withAnimation(reduceMotion ? nil : OnboardingDesign.ease(0.45)) {
            progress = 1
        }
        go(to: .name)
    }

    private func startIntro() {
        guard stage == .reveal, progress < 0.5 else { return }
        guard !reduceMotion else {
            progress = 0.5
            return
        }
        introTask?.cancel()
        introTask = Task { @MainActor in
            try? await Task.sleep(for: OnboardingDesign.introDelay)
            guard !Task.isCancelled, stage == .reveal else { return }
            withAnimation(OnboardingDesign.ease(OnboardingDesign.introDuration)) {
                progress = 0.5
            }
        }
    }

    // MARK: - Такт 2: імʼя

    @AppStorage(HeroGreeting.storageKey) private var storedName = ""
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var nameStage: some View {
        VStack(spacing: 26) {
            Text("Як до тебе звертатися?")
                .font(.emDisplay(40, weight: .light))
                .tracking(-0.03 * 40)
                .foregroundStyle(OnboardingDesign.ink)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.emUI(15))
                    .foregroundStyle(OnboardingDesign.ink)
                    .focused($nameFocused)
                    .onSubmit(goToGesture)
                    .onChange(of: name) { _, new in
                        if new.count > HeroGreeting.maxLength {
                            name = String(new.prefix(HeroGreeting.maxLength))
                        }
                    }
                    .overlay(alignment: .leading) {
                        if name.isEmpty {
                            Text("Твоє імʼя")
                                .font(.emUI(15))
                                .foregroundStyle(Color(hex: "#1F2E2B").opacity(0.4))
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.leading, 20)

                coralButton("Далі", action: goToGesture)
            }
            .padding(6)
            .frame(width: 360)
            .background(
                Capsule().fill(OnboardingDesign.pillFill)
                    .overlay(Capsule().strokeBorder(OnboardingDesign.pillStroke, lineWidth: 1))
            )
        }
        .frame(width: D.width, height: D.height)
        .onAppear {
            name = storedName
            nameFocused = true
        }
    }

    private func goToGesture() {
        // Enter у полі спрацьовує і як onSubmit, і як defaultAction кнопки
        guard stage == .name else { return }
        // Порожнє імʼя — теж відповідь: вітатимемось без імені
        HeroGreeting.store(name)
        nameFocused = false
        go(to: .gesture)
        beginGestureStage()
    }

    // MARK: - Такт 3: жест
    //
    // Від прототипу тут лишився тільки текст. Замість намальованої
    // панельки в кутку вікна вмикаємо СПРАВЖНЮ підказку-світіння на краю
    // екрана і чекаємо справжньої дії: зараховується показ панелі з
    // причиною .edgeHover або .hotkey (див. PanelShowReason).

    @AppStorage(HotkeyManager.displayKey) private var hotkeyDisplay = "⌥E"
    /// Вимкнений «Виклик при наведенні» (Settings → Доступ): жест краю
    /// НЕ спрацює - PanelController мовчки відмовляє. Тоді такт вчить
    /// хоткея, а не краю (ревʼю 2026-08-12 №8)
    @AppStorage("edgeHoverEnabled") private var edgeHoverEnabled = true
    @State private var gestureDone = false
    @State private var showFallback = false
    @State private var fallbackTimer: Task<Void, Never>?
    /// Демонстрація жесту привидом-курсором зараз іде
    @State private var demoRunning = false

    private var gestureStage: some View {
        VStack(spacing: 0) {
            Text(gestureDone ? "Ось вона. Завжди тут." : "Панель поруч")
                .font(.emDisplay(40, weight: .light))
                .tracking(-0.03 * 40)
                .foregroundStyle(OnboardingDesign.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            if gestureDone {
                Text("або \(hotkeyDisplay) з клавіатури")
                    .font(.emUI(13))
                    .foregroundStyle(OnboardingDesign.inkSoft)
                    .padding(.bottom, 24)
                coralButton(OnboardingSeeder.didSeedStickersThisLaunch ? "Далі" : "Почнімо") {
                    if OnboardingSeeder.didSeedStickersThisLaunch {
                        go(to: .stickies)
                    } else {
                        OnboardingWindowController.shared.finish()
                    }
                }
            } else {
                Text(edgeHoverEnabled
                     ? "Наведи курсор на правий край екрана - панель Embar висунеться сама."
                     : "Натисни \(hotkeyDisplay) - і панель Embar висунеться з правого краю.")
                    .font(.emUI(15))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingDesign.inkSoft)
                    .frame(width: D.bodyTextWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                if showFallback {
                    glassButton("Покажи мені", action: runGestureDemo)
                        .disabled(demoRunning)
                        .opacity(demoRunning ? 0.5 : 1)
                }
            }
        }
        .frame(width: D.width, height: D.height)
        .onReceive(NotificationCenter.default.publisher(for: .embarPanelDidShow)) { note in
            let raw = note.userInfo?["reason"] as? String
            guard let reason = raw.flatMap(PanelShowReason.init(rawValue:)) else { return }
            switch reason {
            case .edgeHover, .hotkey:
                markGestureDone()
            case .dockClick:
                // Клік по Dock - найприродніший спосіб «повернути
                // застосунок». Панель уже видима, наполягати на жесті
                // безглуздо, а перший же ⌥E СХОВАВ би її - рівно після
                // слів «завжди тут» (ревʼю №4). Зараховуємо
                markGestureDone()
            case .launch, .programmatic:
                break
            }
        }
        .onDisappear { fallbackTimer?.cancel() }
    }

    /// «Покажи мені»: спершу привид-курсор пливе до краю — щоб було
    /// видно, ЯКИЙ саме жест, — і аж тоді панель виїжджає сама
    private func runGestureDemo() {
        guard !demoRunning else { return }
        demoRunning = true
        OnboardingEdgeHintController.shared.hide()
        OnboardingGhostCursor.shared.play {
            // Панель беремо з контролера, а якщо його раптом немає — з
            // делегата: кнопка мусить спрацьовувати завжди
            let panel = OnboardingWindowController.shared.panelController
                ?? AppDelegate.current?.panelController
            panel?.show(reason: .programmatic)
            markGestureDone()
            demoRunning = false
        }
    }

    private func beginGestureStage() {
        let panel = OnboardingWindowController.shared.panelController
        // Закріплену панель не чіпаємо — вчити жесту нема на чому,
        // просто зараховуємо такт
        if panel?.isPinned == true, panel?.isOnScreen == true {
            markGestureDone()
            return
        }
        panel?.hideForOnboarding()
        // Світіння вчить САМЕ краю - з вимкненим hover воно обіцяло б
        // жест, який мовчки не працює (ревʼю №8)
        if edgeHoverEnabled { OnboardingEdgeHintController.shared.show() }
        fallbackTimer?.cancel()
        fallbackTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, !gestureDone else { return }
            withAnimation(OnboardingDesign.ease(0.4)) { showFallback = true }
        }
    }

    private func markGestureDone() {
        guard !gestureDone else { return }
        withAnimation(reduceMotion ? nil : OnboardingDesign.ease(0.45)) {
            gestureDone = true
            showFallback = false
        }
        fallbackTimer?.cancel()
        OnboardingEdgeHintController.shared.hide()
    }

    // MARK: - Такт 4: навчальні стіки (лише якщо реально сіялись)

    private var stickiesStage: some View {
        VStack(spacing: 0) {
            Text("На стіні тебе вже чекають навчальні стіки.")
                .font(.emDisplay(34, weight: .light))
                .tracking(-0.03 * 34)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(OnboardingDesign.ink)
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Text("Вони покажуть решту. Це звичайні стіки - виконуй, видаляй, переписуй.")
                .font(.emUI(15))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(OnboardingDesign.inkSoft)
                .frame(width: D.bodyTextWidth)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            coralButton("Почнімо") { OnboardingWindowController.shared.finish() }

            // Один ненавʼязливий рядок про модель - покупка доступна з
            // першого дня (SPEC §15.77д). Пейвол відкривається ПОВЕРХ
            // картки знайомства (обидва .statusBar, пізніше вікно вище)
            Button { PaywallWindowController.shared.show() } label: {
                Text("Перші 14 днів безкоштовно. Далі: як підтримати")
                    .font(.emUI(12))
                    .foregroundStyle(OnboardingDesign.inkSoft)
                    .underline()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .frame(width: D.width, height: D.height)
    }

    // MARK: - Кнопки

    private func coralButton(_ label: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.emUI(14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(Capsule().fill(OnboardingDesign.coralFill))
                .shadow(color: OnboardingDesign.coral.opacity(0.3), radius: 11, y: 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func glassButton(_ label: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.emUI(14, weight: .medium))
                .foregroundStyle(OnboardingDesign.ink)
                .padding(.horizontal, 30)
                .padding(.vertical, 13)
                .background(Capsule().fill(OnboardingDesign.pillFill))
                .overlay(Capsule().strokeBorder(OnboardingDesign.pillStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

}
