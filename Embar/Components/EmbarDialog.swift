//
//  EmbarDialog.swift
//  Embar
//
//  Оболонка маленького віконця-питання: ловець кліків (клік повз —
//  закрити), картка 256pt r16 з тінню, заголовок по центру, під ним —
//  пігулки вибору (ConfirmChoicePill). Затемнення під віконцем — НЕ
//  чорний скрим, а світлий блюр вмісту: господар вішає .dialogDimmed
//  (нижче) перед своїм .overlay.
//
//  Винесено з ConfirmDeleteDialog (2026-08-03), коли зʼявився другий
//  такий діалог — питання про перезапуск після зміни мови. Один контрол
//  має виглядати однаково скрізь, тож замість копії chrome обидва
//  користуються цією оболонкою.
//

import SwiftUI

struct EmbarDialog<Content: View>: View {
    let title: LocalizedStringKey
    /// Дрібніший рядок під заголовком - для питань, де самого заголовка
    /// замало (напр. куди подінуться навчальні стіки після видалення)
    var note: LocalizedStringKey? = nil
    var onCancel: () -> Void
    /// Пігулки вибору — зазвичай ConfirmChoicePill
    @ViewBuilder let choices: Content
    /// Текстова кнопка внизу; nil — її немає (тоді «відмова» це одна з пігулок)
    var dismissLabel: LocalizedStringKey?

    init(title: LocalizedStringKey,
         note: LocalizedStringKey? = nil,
         dismissLabel: LocalizedStringKey? = nil,
         onCancel: @escaping () -> Void,
         @ViewBuilder choices: () -> Content) {
        self.title = title
        self.note = note
        self.dismissLabel = dismissLabel
        self.onCancel = onCancel
        self.choices = choices()
    }

    var body: some View {
        ZStack {
            // Ловець кліків повз віконце (майже прозорий, як у стіків).
            // Затемнення тут НЕ малюється: господар вішає .dialogDimmed
            // на вміст під overlay - той самий світлий блюр, що при
            // розгорнутому стіку (фідбек 2026-08-12)
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            VStack(spacing: 14) {
                Text(title)
                    .font(.emUI(13, weight: .medium))
                    .foregroundStyle(EmbarColors.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.emUI(11.5))
                        .foregroundStyle(EmbarColors.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -6)
                }
                VStack(spacing: 6) { choices }
                if let dismissLabel {
                    Button(action: onCancel) {
                        Text(dismissLabel)
                            .font(.emUI(11.5))
                            .foregroundStyle(EmbarColors.ink3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 16, bottom: 14, trailing: 16))
            .frame(width: 256)
            .background(RoundedRectangle(cornerRadius: 16).fill(EmbarColors.card))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
        }
        .transition(.opacity)
    }
}

extension View {
    /// Підкладка під віконце-питання: вміст мʼяко розмивається і тане до
    /// фону панелі - байт-у-байт як при розгорнутому стіку
    /// (StickiesView, blur 2 / opacity 0.35 / easeInOut 0.2), замість
    /// чорного затемнення (фідбек 2026-08-12). Вішати на вміст ПЕРЕД
    /// .overlay з діалогом, інакше розмиється і саме віконце.
    func dialogDimmed(_ active: Bool) -> some View {
        blur(radius: active ? 2 : 0)
            .opacity(active ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

/// Пігулка вибору «віконця-питання» — спільна мова для діалогів у панелі
/// і inline-питання у стіку-віджеті на столі (SPEC §2.7)
struct ConfirmChoicePill: View {
    let label: LocalizedStringKey
    var fill: Color = .black.opacity(0.06)
    var text: Color = EmbarColors.ink2
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.emUI(11.5, weight: .medium))
                .foregroundStyle(text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
