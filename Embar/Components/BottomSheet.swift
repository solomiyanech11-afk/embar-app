//
//  BottomSheet.swift
//  Embar
//
//  Власний bottom-sheet усередині панелі (не системний sheet — той відкриває
//  окреме вікно). Скрим + slide-up + drag-вниз для закриття. SPEC §7, прототип
//  `.note-settings-*`. Кути 20/20/16/16 (нижні збігаються з радіусом панелі).
//
//  ❗ БЕЗ removal-transition: у нашій панелі SwiftUI прибирає лист із
//  композиції вікна миттєво, а transition анімує вже невидимі шари —
//  діагностика 2026-08-14 (лог користувача): трек шарів плавний 0.28с,
//  а на екрані лист зникав різко. Тому рух робить явний offset на
//  ЗМОНТОВАНОМУ листі (та сама механіка, що видимий drag), і лише
//  після виїзду за край лист знімається з дерева.
//

import SwiftUI

private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Чи лист у дереві. Живе довше за isPresented: при закритті лист
    /// СПОЧАТКУ з'їжджає (slideOut), і лише потім знімається
    @State private var shown = false
    /// true - лист за нижнім краєм (і скрим прозорий). Анімується явно;
    /// сам факт монтування/зняття не анімується ніколи
    @State private var slideOut = true
    @State private var dragOffset: CGFloat = 0
    /// Виміряна висота листа - дистанція виїзду за край
    @State private var sheetHeight: CGFloat = 0
    /// Захист від гонки «закрили → одразу відкрили»: застаріле
    /// відкладене зняття з дерева не спрацює
    @State private var closeGeneration = 0

    private let curve = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.28)
    /// Запас понад висоту листа, щоб виїхала і його тінь
    private var slideDistance: CGFloat {
        sheetHeight > 0 ? sheetHeight + 80 : 900
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if shown {
                    ZStack(alignment: .bottom) {
                        // Скрим: гасне разом із виїздом листа; клік повз - закрити.
                        // ❗ .allowsHitTesting на час виїзду: .opacity(0), на
                        // відміну від зняття з дерева, кліки НЕ пропускає — і
                        // невидимий скрим на всю панель зʼїдав перший клік
                        // ще 0.32 с після закриття (ревʼю 2026-08-18, знахідка 3;
                        // той самий клас «мертвої стіни», що лікували 2026-08-11)
                        Color.black.opacity(0.34)
                            .opacity(slideOut ? 0 : 1)
                            .ignoresSafeArea()
                            .allowsHitTesting(!slideOut)
                            .onTapGesture { isPresented = false }

                        sheet
                            .offset(y: dragOffset + (slideOut ? slideDistance : 0))
                    }
                    // Слайд-ап відкриття: лист монтується за краєм
                    // (slideOut=true) і їде на місце вже ЗМОНТОВАНИМ
                    .onAppear {
                        withAnimation(curve) { slideOut = false }
                    }
                }
            }
            .onChange(of: isPresented) { _, open in
                closeGeneration += 1
                if open {
                    dragOffset = 0
                    if shown {
                        // Повторне відкриття, поки лист ще з'їжджав
                        withAnimation(curve) { slideOut = false }
                    } else {
                        slideOut = true   // стартова позиція; onAppear поїде
                        shown = true
                    }
                } else {
                    beginClose()
                }
            }
            .onAppear {
                shown = isPresented
                slideOut = !isPresented
            }
    }

    /// Закриття: явний виїзд за край на змонтованому листі, потім тихе
    /// (без анімації) зняття з дерева
    private func beginClose() {
        withAnimation(curve) { slideOut = true }
        let generation = closeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard generation == closeGeneration else { return }
            shown = false
            dragOffset = 0
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            // Drag-handle
            Capsule()
                .fill(EmbarColors.ink4.opacity(0.5))
                .frame(width: 38, height: 4)
                .padding(.top, 6)
                .padding(.bottom, 12)
            sheetContent()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
        .embarOverlaySurface()
        .clipShape(.rect(topLeadingRadius: 20, bottomLeadingRadius: 16,
                         bottomTrailingRadius: 16, topTrailingRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 16, y: -8)
        // Висота листа потрібна для дистанції виїзду
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { sheetHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in
                        sheetHeight = height
                    }
            }
        }
        .gesture(
            // ❗ .global, не дефолтний .local: локальний простір їде разом
            // із листом, який ми ж і зсуваємо dragOffset-ом — translation
            // стрибав між «зсунуто» і «ні», лист тремтів під курсором
            // (B1 тест-плану). Глобальний простір нерухомий — рух чистий
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 80 {
                        isPresented = false
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

/// Лист, привʼязаний до МОДЕЛІ, а не до Bool (ревʼю 2026-08-18, знахідка 2).
///
/// Bool-варіант нижче має пастку для optional-моделей: закриття нулить
/// модель одразу, а лист живе ще 0.32 с, поки виїжджає. Живий
/// `@ViewBuilder` за цей час переобчислює `if let job` у порожнечу — і
/// донизу сповзає порожня оболонка з самою ручкою-капсулою, та ще й
/// висота листа схлопується посеред анімації.
///
/// Тут модель тримає сам модифікатор: поки лист їде, він показує ту саму
/// картку, з якою людина прощається. Копія живе рівно до кінця виїзду.
///
/// ⚠️ Копія знімається в момент появи моделі, тож модель має бути
/// незмінною за час показу (кроп-джоби саме такі). Якщо колись
/// знадобиться лист, вміст якого змінюється, — Bool-варіант підходить
/// краще, бо там вміст завжди живий.
private struct BottomSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let sheetContent: (Item) -> SheetContent

    /// Модель, з якою лист виїжджає (після виїзду відпускаємо — інакше
    /// картинка кропу висіла б у памʼяті до наступного разу)
    @State private var retained: Item?

    func body(content: Content) -> some View {
        content
            .embarBottomSheet(isPresented: Binding(
                get: { item != nil },
                set: { open in if !open { item = nil } }
            )) {
                if let shown = item ?? retained {
                    sheetContent(shown)
                }
            }
            .onChange(of: item?.id) { _, _ in
                if let item {
                    retained = item
                    return
                }
                Task { @MainActor in
                    // Трохи довше за виїзд (0.28 с руху + запас)
                    try? await Task.sleep(for: .milliseconds(450))
                    // Могли встигнути відкрити знову — тоді копія потрібна
                    if item == nil { retained = nil }
                }
            }
    }
}

extension View {
    func embarBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented, sheetContent: content))
    }

    /// Лист для optional-моделі: закриття не лишає порожньої оболонки
    /// (див. BottomSheetItemModifier)
    func embarBottomSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(BottomSheetItemModifier(item: item, sheetContent: content))
    }
}
