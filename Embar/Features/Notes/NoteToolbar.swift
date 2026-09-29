//
//  NoteToolbar.swift
//  Embar
//
//  Плаваюча пігулка-тулбар редактора (SPEC §3.2): роль абзацу · Bold/Italic ·
//  колір тексту · вирівнювання · перо. Кнопки читають model.selection для
//  активного стану; списки/цитата/фото — кроки 6/10.
//

import SwiftUI
import AppKit

struct NoteToolbar: View {
    @ObservedObject var model: NoteEditorModel

    @State private var colorOpen = false
    @State private var highlightOpen = false
    @State private var alignOpen = false
    @State private var listOpen = false
    @State private var photoOpen = false
    /// Скільки кнопок зараз під мишею (фідбек 2026-07-28: над кнопками —
    /// рука). Лічильник, не Bool: при переході між сусідніми кнопками
    /// enter нової може прийти раніше за exit старої
    @State private var handHoverCount = 0

    private var sel: NoteSelectionState { model.selection }

    var body: some View {
        HStack(spacing: 3) {
            hand(roleMenu)
            sep
            hand(btn("bold", active: sel.bold) { model.toggleBold() })
            hand(btn("italic", active: sel.italic) { model.toggleItalic() })
            hand(colorButton)
            sep
            hand(alignButton)
            hand(listButton)
            hand(btn("text.quote", active: sel.quote) { model.toggleQuote() })
            sep
            hand(highlightButton)
            hand(photoButton)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(EmbarColors.surface.opacity(0.97))
                .overlay(Capsule().stroke(Color.black.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.09), radius: 8, y: 2)
        )
        // Тулбар плаває НАД text view, а той ставить I-beam на всю свою
        // область — без явного курсора миша лишалась «текстовою»
        // (фідбек 2026-07-05). Continuous: text view перевстановлює курсор
        // на кожен рух миші, тож разового .set() недостатньо. Над кнопками
        // — рука (фідбек 2026-07-28), рішення в ОДНОМУ місці за
        // лічильником — два вкладені onContinuousHover воювали б за курсор
        .onContinuousHover { phase in
            if case .active = phase {
                (handHoverCount > 0 ? NSCursor.pointingHand : NSCursor.arrow)
                    .set()
            }
        }
    }

    /// Кнопка рахує себе в handHoverCount, поки під мишею. ❗ Лише для
    /// верхнього ряду тулбара — кнопки У ПОПАПАХ живуть в окремих вікнах,
    /// їхній exit при закритті попапа не гарантований і лічильник би тік
    private func hand<V: View>(_ view: V) -> some View {
        view.onHover { inside in handHoverCount += inside ? 1 : -1 }
    }

    private var sep: some View {
        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 16).padding(.horizontal, 2)
    }

    /// Єдиний білдер іконки-кнопки тулбара і флаявтів (був продубльований
    /// 4 рази з дрейфом: у копії тулбара бракувало contentShape — мертві
    /// зони кліку; code review, reuse)
    private func btn(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? EmbarColors.ink : EmbarColors.ink2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color.black.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Роль абзацу (H1/H2/P/S)

    private var roleMenu: some View {
        Menu {
            roleItem(.h1, "Заголовок 1")
            roleItem(.h2, "Заголовок 2")
            roleItem(.p, "Абзац")
            roleItem(.s, "Дрібний")
        } label: {
            HStack(spacing: 2) {
                Text(roleLabel).font(.emUI(12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(EmbarColors.ink2)
            .frame(minWidth: 34, minHeight: 28)
            .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func roleItem(_ r: ParagraphRole, _ label: LocalizedStringKey) -> some View {
        Button {
            model.setRole(r)
        } label: {
            if sel.role == r { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
    }

    private var roleLabel: String {
        switch sel.role {
        case .h1: return "H1"
        case .h2: return "H2"
        case .p: return "P"
        case .s: return "S"
        }
    }

    // MARK: - Вирівнювання (іконковий флаявт, як у прототипі)

    private var alignButton: some View {
        Button { alignOpen = true } label: {
            Image(systemName: currentAlignIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EmbarColors.ink2)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $alignOpen, arrowEdge: .bottom) {
            HStack(spacing: 4) {
                btn("text.alignleft", active: sel.alignment == .left || sel.alignment == .natural) {
                    model.setAlignment(.left); alignOpen = false
                }
                btn("text.aligncenter", active: sel.alignment == .center) {
                    model.setAlignment(.center); alignOpen = false
                }
                btn("text.alignright", active: sel.alignment == .right) {
                    model.setAlignment(.right); alignOpen = false
                }
            }
            .padding(8)
        }
    }

    private var currentAlignIcon: String {
        switch sel.alignment {
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        default: return "text.alignleft"
        }
    }

    // MARK: - Списки (флаявт із гліфами маркерів)

    private var listButton: some View {
        Button { listOpen = true } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sel.list != nil ? EmbarColors.ink : EmbarColors.ink2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(sel.list != nil ? Color.black.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $listOpen, arrowEdge: .bottom) {
            HStack(spacing: 4) {
                listGlyph("•", .bullet)
                listGlyph("1.", .number)
                listGlyph("→", .arrow)
                listGlyph("▸", .triangle)
            }
            .padding(8)
        }
    }

    private func listGlyph(_ glyph: String, _ style: ListStyle) -> some View {
        Button {
            model.toggleList(style)
            listOpen = false
        } label: {
            Text(glyph)
                .font(.emUI(13, weight: .medium))
                .foregroundStyle(sel.list == style ? EmbarColors.ink : EmbarColors.ink2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(sel.list == style ? Color.black.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Фото (флаявт розкладок 1/2/3)

    private var photoButton: some View {
        Button { photoOpen = true } label: {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EmbarColors.ink2)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $photoOpen, arrowEdge: .bottom) {
            HStack(spacing: 4) {
                photoLayout("rectangle", columns: 1)
                photoLayout("rectangle.split.2x1", columns: 2)
                photoLayout("rectangle.split.3x1", columns: 3)
            }
            .padding(8)
        }
    }

    private func photoLayout(_ icon: String, columns: Int) -> some View {
        btn(icon, active: false) {
            photoOpen = false
            // Дати попаверу закритись до модального діалогу вибору файлів
            DispatchQueue.main.async { model.insertPhotoRow(columns: columns) }
        }
    }

    // MARK: - Колір тексту

    private var colorButton: some View {
        Button { colorOpen = true } label: {
            Image(systemName: "a.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sel.textColor != nil ? Color(nsColor: (sel.textColor ?? .ink).nsColor) : EmbarColors.ink2)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $colorOpen, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(BodyTextColor.allCases, id: \.self) { c in
                    Button {
                        model.setTextColor(c == .ink ? nil : c)
                        colorOpen = false
                    } label: {
                        Circle().fill(Color(nsColor: c.nsColor)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: c == .ink ? 1 : 0))
                            .overlay(Circle().stroke(EmbarColors.ink, lineWidth: sel.textColor == c ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    model.setTextColor(nil)
                    colorOpen = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(EmbarColors.ink3)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
    }

    // MARK: - Перо (highlight)

    private var highlightButton: some View {
        Button { highlightOpen = true } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sel.highlight != nil ? EmbarColors.ink : EmbarColors.ink2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(sel.highlight != nil ? Color.black.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $highlightOpen, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(HighlightColor.allCases, id: \.self) { c in
                    Button {
                        model.toggleHighlight(c)
                        highlightOpen = false
                    } label: {
                        Circle().fill(Color(nsColor: c.nsColor)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(EmbarColors.ink, lineWidth: sel.highlight == c ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}
