//
//  PaywallView.swift
//  Embar
//
//  Екран Embar Pro - «glass» редизайн за design_handoff_paywall
//  (2026-09-17): темний модал зі світіннями, шапка з іконкою і
//  Fraunces-заголовком, пігулка днів trial, дві СКЛЯНІ картки планів
//  (перемикаються, типово lifetime), один білий CTA, юридичний рядок
//  від плану, футер Restore/Privacy/EULA.
//
//  Логіка станів незмінна (SPEC §15.77): підзаголовок минулого trial
//  тримає лічильник думок; офлайн/загрузка/успіх - ті самі стани в
//  новому одязі. Ціни - StoreKit через offerings.current.
//

import AppKit
import RevenueCat
import SwiftUI

struct PaywallView: View {
    @ObservedObject var model: PaywallModel

    private typealias D = PaywallDesign

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Фаза «дихання» знака під час очікування покупки
    @State private var breathing = false

    private var breathAnimation: Animation? {
        guard model.phase == .purchasing, !reduceMotion else { return nil }
        return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }

    private var trialExpired: Bool {
        switch model.access {
        case .trial, .pro: return false
        case .readOnly, .open: return true
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if model.phase == .success {
                    successContent
                } else {
                    mainContent
                }
            }
            // Білий текст на світлому склі: мʼяка тінь, як у референсі -
            // читається на будь-яких шпалерах
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            // ❗ Рамка розміру вікна з вирівнюванням догори (фідбек
            // 2026-09-17): без неї вміст, що не вміщався по висоті,
            // розтягував ZStack, той центрувався в рамці вікна - хрестик
            // їхав угору, а скло (дитина стека) не діставало низу, і під
            // футером просвічував робочий стіл. Тепер зайве відрізається
            // знизу, каркас не рухається
            .frame(width: D.width, height: D.height, alignment: .top)
            .clipped()
            // Закриття - червона кнопка вікна зліва вгорі (утилітарна
            // смужка, SPEC §15.78); власного хрестика більше немає. Esc
            // ловить PaywallPanel.cancelOperation
        }
        .frame(width: D.width, height: D.height)
        // Скло - ФОН рамки вікна, не дитина стека: тягнеться на повну
        // висоту незалежно від вмісту. Явна рамка всередині - бо кола
        // світінь (640/720) інакше роздули б фон ширше за вікно
        .background(
            backdrop
                .frame(width: D.width, height: D.height)
                .allowsHitTesting(false))
        // ❗ Кут ЦИРКУЛЯРНИЙ, не .continuous: скло малює NSVisualEffectView
        // через layer.cornerRadius, а він завжди циркулярний. З
        // continuous-кліпом у розі жили ДВІ різні криві (скло і рамка) -
        // читалось як кривий край і збита посадка хрестика
        // (фідбек 2026-09-17). Хендоф теж має CSS border-radius = дуга
        .clipShape(RoundedRectangle(cornerRadius: D.windowRadius))
        .overlay(
            RoundedRectangle(cornerRadius: D.windowRadius)
                .strokeBorder(D.modalBorder, lineWidth: 1))
        // Тости цього вікна - той самий шар, що в панелі; пігулка стає
        // над футером (Restore/Privacy/EULA), не на ньому
        .toastLayer(model.toasts, miniBottomPadding: D.bottomInset + 48)
        .task { await model.load() }
        .task(id: model.phase) {
            breathing = model.phase == .purchasing && !reduceMotion
        }
    }

    // MARK: - Тло: темна плита + два світіння (хендоф: red 640 зверху
    // ліворуч, teal 720 знизу; блюр і прозорість декоративні)

    private var backdrop: some View {
        ZStack {
            // Спільне світле скло стіків: behindWindow blur+saturate
            // без молока - робочий стіл світиться крізь модал
            BehindWindowGlass(cornerRadius: D.windowRadius)
            D.bg.opacity(D.bgTintOpacity)
            Circle()
                .fill(RadialGradient(
                    colors: [D.accent.opacity(0.45), .clear],
                    center: .center, startRadius: 0, endRadius: 320))
                .frame(width: 640, height: 640)
                .blur(radius: 30)
                .offset(x: -D.width * 0.45, y: -D.height * 0.38)
            Circle()
                .fill(RadialGradient(
                    colors: [D.tealGlow.opacity(0.32), .clear],
                    center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 720, height: 720)
                .blur(radius: 40)
                .offset(x: D.width * 0.2, y: D.height * 0.52)
            D.glassWash
        }
    }

    // MARK: - Основний стан

    // Явні зазори замість VStack(spacing:) зі Spacer-ом: той додавав
    // проміжок і ДО, і ПІСЛЯ спейсера (40 замість 20), і бюджет висоти
    // не сходився. Числа - у коментарі до PaywallDesign.height
    private var mainContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, D.inset)

            plansArea
                .padding(.horizontal, D.inset)
                .padding(.top, 20)

            VStack(spacing: 12) {
                ctaButton
                if model.waitIsSlow {
                    // Вихід замість вічного очікування: відповідь старої
                    // спроби фазу вже не чіпатиме, але покупку, що таки
                    // пройшла, EntitlementStore застосує
                    Button { model.giveUpWaiting() } label: {
                        Text("Щось затягнулось. Спробувати ще раз?")
                            .font(.emUI(11.5, weight: .medium))
                            .foregroundStyle(D.text75)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                legalLine
                if trialExpired {
                    Text("Поки ви вирішуєте, все записане відкрите: читати, копіювати, видаляти. Нові записи чекають на план.")
                        .font(.emUI(11))
                        .foregroundStyle(D.text40)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520)
                }
            }
            .padding(.horizontal, D.inset)
            .padding(.top, 20)

            Spacer(minLength: 8)

            footer
                .padding(.horizontal, D.inset)
                .padding(.bottom, D.bottomInset)
        }
    }

    // MARK: - Шапка: іконка, заголовок, пігулка trial, підзаголовок

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: D.accent.opacity(0.35), radius: 20, y: 12)
                // Очікування покупки - мʼяке дихання знака замість
                // спінера (прозорість, без обертання). Reduce Motion:
                // нерухомо. Анімація живе ЛИШЕ у фазі purchasing, тож
                // repeatForever не лишається висіти після виходу з неї
                .opacity(breathing ? 0.45 : 1)
                .animation(breathAnimation, value: breathing)

            Text(verbatim: "Embar Pro")
                .font(.emDisplay(38, weight: .regular))
                .tracking(-0.01 * 38)
                .foregroundStyle(D.text)

            if case .trial(let days) = model.access {
                HStack(spacing: 7) {
                    Circle().fill(D.accent).frame(width: 6, height: 6)
                    Text(String(
                        localized: "Лишилось \(days) дн. пробного періоду",
                        comment: "Пігулка в шапці пейвола; день/дні/днів у каталозі"))
                        .font(.emUI(12))
                        .foregroundStyle(D.text85)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12),
                                                lineWidth: 1))
            }

            subtitle
                .font(.emUI(13.5))
                .foregroundStyle(D.text65)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                // Рівно два рядки: ширший блок + запас на стиск для
                // найдовшого випадку (uk, трицифровий лічильник думок)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: D.headerTextWidth)
        }
    }

    /// Trial триває - загальний рядок хендофа (дні вже в пігулці);
    /// минув - погоджені стани з лічильником думок (SPEC §15.77е)
    private var subtitle: Text {
        switch model.access {
        case .trial:
            return Text("Оберіть, як продовжити. У будь-якому разі - все відкрито.")
        case .pro, .readOnly, .open:
            if model.thoughtCount >= 20 {
                return Text(String(
                    localized: "За 14 днів тут зʼявилось \(model.thoughtCount) ваших думок. Щоб вони зʼявлялись далі, оберіть план: одна кава на місяць або одна оплата назавжди.",
                    comment: "Пейвол: підзаголовок, trial минув, думок багато; думка/думки/думок у каталозі"))
            }
            return Text("14 днів разом пролетіли швидко. Далі за одну каву на місяць або одну оплату назавжди.")
        }
    }

    // MARK: - Картки планів

    @ViewBuilder
    private var plansArea: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
                .frame(height: D.cardHeight)
        case .offline:
            VStack(spacing: 12) {
                Text("Не вдалося завантажити ціни. Перевірте інтернет і спробуйте ще раз.")
                    .font(.emUI(12.5))
                    .foregroundStyle(D.text65)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.load() }
                } label: {
                    Text("Спробувати ще раз")
                        .font(.emUI(12.5, weight: .medium))
                        .foregroundStyle(D.text85)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12),
                                                        lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .frame(height: D.cardHeight)
        case .ready, .purchasing:
            HStack(alignment: .top, spacing: 18) {
                planCard(.monthly, package: model.monthly)
                planCard(.lifetime, package: model.lifetime)
            }
            .opacity(model.phase == .purchasing ? 0.5 : 1)
        case .success:
            EmptyView()
        }
    }

    @ViewBuilder
    private func planCard(_ plan: PaywallModel.Plan,
                          package: Package?) -> some View {
        // Ціна ВИКЛЮЧНО зі StoreKit: пакета немає - картки немає
        // (жодних власних валют і фолбеків - блокер 2026-09-17)
        if let package {
            let isSelected = model.selected == plan
            Button {
                withAnimation(D.select) { model.selected = plan }
            } label: {
                VStack(alignment: .leading, spacing: D.cardSpacing) {
                    Text(plan == .lifetime ? "Назавжди" : "Щомісяця")
                        .font(.emUI(12, weight: .medium))
                        .foregroundStyle(D.text60)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: package.localizedPriceString)
                            .font(.emDisplay(30, weight: .regular))
                            .foregroundStyle(D.text)
                        Text(plan == .lifetime ? "одна оплата" : "/міс")
                            .font(.emUI(12.5))
                            .foregroundStyle(D.text55)
                    }

                    // Слот приміток фіксованої висоти - лінії-роздільники
                    // обох карток на одному рівні (D.cardNoteSlot)
                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if plan == .lifetime {
                                // Рахується з реальних цін обох пакетів;
                                // нема з чого рахувати - рядок порожній
                                if let months = model.monthsToPayOff {
                                    Text("Окупається за \(months) міс.")
                                } else {
                                    Text(verbatim: " ")
                                }
                            } else {
                                Text("Скасувати можна будь-коли")
                            }
                        }
                        .font(.emUI(11.5))
                        .foregroundStyle(D.text50)
                        if plan == .monthly {
                            // Умови підписки ПОРУЧ із пропозицією
                            // (Guideline 3.1.2): видимі завжди, бо
                            // картка завжди на екрані, хоч би який план
                            // обрано (фідбек 2026-09-17)
                            Text("Поновлюється щомісяця, скасувати можна в налаштуваннях App Store")
                                .font(.emUI(10))
                                .foregroundStyle(D.text40)
                                .lineSpacing(0)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(height: D.cardNoteSlot, alignment: .topLeading)

                    Rectangle().fill(D.divider).frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        if plan == .lifetime {
                            cardFeature("Усе з місячного, назавжди")
                            cardFeature("Одна оплата, жодних поновлень")
                            cardFeature("Усі майбутні функції включено")
                        } else {
                            cardFeature("Створюйте без обмежень: стіки, нотатки, блокноти")
                            cardFeature("Усі майбутні функції включено")
                            cardFeature("Зроблено однією людиною. Ваша оплата і є підтримка.")
                        }
                    }

                    Spacer(minLength: 0)

                    selectRow(isSelected: isSelected)
                }
                .padding(EdgeInsets(top: 20, leading: 18, bottom: 16, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: D.cardHeight)
                .background(cardBackground(isSelected: isSelected))
                .overlay(alignment: .topLeading) {
                    if plan == .lifetime {
                        Text("Найкращий вибір")
                            .textCase(.uppercase)
                            .font(.emUI(10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(D.accent))
                            .shadow(color: D.accent.opacity(0.45), radius: 10, y: 6)
                            .offset(x: 18, y: -11)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: D.cardRadius))
            }
            .buttonStyle(.plain)
            .disabled(model.phase != .ready)
        }
    }

    private func cardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: D.cardRadius, style: .continuous)
            .fill(isSelected
                  ? AnyShapeStyle(LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(D.cardBg))
            .overlay(RoundedRectangle(cornerRadius: D.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? D.cardSelectedBorder : D.cardBorder,
                              lineWidth: 1))
            .shadow(color: isSelected ? D.accent.opacity(0.22) : .clear,
                    radius: 35, y: 24)
    }

    private func cardFeature(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 16, height: 16)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.emUI(11.5))
                .lineSpacing(2)
                .foregroundStyle(D.text85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectRow(isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().strokeBorder(
                    isSelected ? Color.white : D.text40, lineWidth: 1.5)
                if isSelected {
                    Circle().fill(D.accent).frame(width: 8, height: 8)
                }
            }
            .frame(width: 15, height: 15)
            Group {
                if isSelected { Text("Обрано") } else { Text("Обрати") }
            }
            .font(.emUI(11.5, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : D.text40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTA і юридичний рядок (залежать від обраного плану)

    private var ctaButton: some View {
        Button {
            if let package = model.selectedPackage {
                Task { await model.purchase(package) }
            }
        } label: {
            Group {
                if model.phase == .purchasing {
                    // Кнопка лишається на місці: спінера немає, очікування
                    // показує «дихання» знака в шапці (фідбек 2026-09-17)
                    Text("Зачекайте…")
                } else if let package = model.selectedPackage {
                    // Ціна в підписі кнопки - рівно та, що StoreKit
                    // покаже в системному діалозі покупки
                    if model.selected == .lifetime {
                        Text("Назавжди за \(package.localizedPriceString)")
                    } else {
                        Text("Продовжити за \(package.localizedPriceString)/міс")
                    }
                }
            }
            .font(.emUI(15, weight: .semibold))
            .foregroundStyle(D.bg)
            .frame(maxWidth: 400)
            .frame(height: 48)
            .background(Capsule().fill(Color.white))
            .shadow(color: Color.white.opacity(0.15), radius: 20, y: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .ready)
        .opacity(model.phase == .ready || model.phase == .purchasing ? 1 : 0.4)
        .keyboardShortcut(.defaultAction)
    }

    /// ОДИН рядок під CTA, лише про обраний план (фідбек 2026-09-17):
    /// текст про автопоновлення живе всередині місячної картки, де він
    /// видимий завжди. Рівно один рядок - бюджет висоти вікна рахує
    /// 14pt: ширина 560 вміщає обидві мови (замір), minimumScaleFactor
    /// - страховка від довшого перекладу
    private var legalLine: some View {
        Group {
            if model.selected == .lifetime {
                Text("Одна оплата. Без підписки й поновлень. Назавжди ваше.")
            } else {
                Text("Місячна підписка поновлюється автоматично, доки ви не скасуєте її в налаштуваннях App Store.")
            }
        }
        .font(.emUI(11.5))
        .foregroundStyle(D.text40)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .frame(maxWidth: 560)
    }

    // MARK: - Успіх

    private var successContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: D.accent.opacity(0.35), radius: 20, y: 12)
                .padding(.bottom, 18)

            if model.wasProOnOpen {
                // Відкрив пейвол, уже маючи Pro - не вітаємо з покупкою
                Text("Embar Pro активний. Дякую за підтримку.")
                    .font(.emUI(15))
                    .foregroundStyle(D.text85)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            } else {
                Text("Дякую.")
                    .font(.emDisplay(44, weight: .regular))
                    .tracking(-0.01 * 44)
                    .foregroundStyle(D.text)
                    .padding(.bottom, 10)
                Text("Embar Pro активовано. Тепер створюйте скільки заманеться.")
                    .font(.emUI(14.5))
                    .foregroundStyle(D.text65)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }

            Spacer(minLength: 0)

            Button { PaywallWindowController.shared.close() } label: {
                Text("Продовжити")
                    .font(.emUI(15, weight: .semibold))
                    .foregroundStyle(D.bg)
                    .frame(maxWidth: 260)
                    .frame(height: 48)
                    .background(Capsule().fill(Color.white))
                    .shadow(color: Color.white.opacity(0.15), radius: 20, y: 10)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Футер

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack {
                Button {
                    Task { await model.restore() }
                } label: {
                    Text("Відновити покупки")
                        .font(.emUI(12.5, weight: .medium))
                        .foregroundStyle(D.text75)
                }
                .buttonStyle(.plain)

                Spacer()

                linkButton("Приватність",
                           url: "https://embar.studio/privacy")
                Text(verbatim: " · ")
                    .font(.emUI(12))
                    .foregroundStyle(D.text35)
                linkButton("Умови користування",
                           url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
            }
        }
    }

    private func linkButton(_ title: LocalizedStringKey, url: String) -> some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            Text(title)
                .font(.emUI(12))
                .foregroundStyle(D.text35)
                .underline()
        }
        .buttonStyle(.plain)
    }

}
