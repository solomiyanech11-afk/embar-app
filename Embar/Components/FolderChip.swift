//
//  FolderChip.swift
//  Embar
//
//  Білий плаваючий чіп папки/стіни для folder-bar (прототип
//  `.reader-folder-chip`). Відрізняється від `Chip` (сірий `.sheet-chip`,
//  для фільтрів у sheet): цей — майже білий із тінню, бо плаває над контентом.
//  Лічильник — бейдж ЛИШЕ на активному чіпі.
//

import SwiftUI

extension String {
    /// Текст для чіпів/пігулок: завжди один рядок, довше ліміту — «…»
    /// (фідбек 2026-07-03: не переносити на другий рядок ніде)
    func truncatedChip(_ limit: Int = 20) -> String {
        count > limit ? String(prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : self
    }
}

struct FolderChip: View {
    let label: String
    var count: Int? = nil
    var isActive: Bool = false
    /// Namespace для морф-перетікання активного фону між чіпами (виняток §7.2-A)
    var morphNS: Namespace.ID? = nil
    /// Видалення контейнера: ×-бейдж на ховері (фідбек 2026-07-07)
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Один рядок, довгі назви — три крапки (фідбек 2026-07-03)
                Text(label.truncatedChip())
                    .font(.emUI(12))
                    .lineLimit(1)
                if isActive, let count {
                    Text("\(count)")
                        .font(.emUI(10, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
            }
            .foregroundStyle(isActive ? Color.white : EmbarColors.ink2)
            // Тексти — миттєво, scoped (бланкетний transaction глушив би
            // і морф-перетікання фону, і рух поверхонь)
            .animation(nil, value: isActive)
            .animation(nil, value: count)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    Capsule().fill(EmbarColors.surface.opacity(0.92))
                    if isActive {
                        if let ns = morphNS {
                            // Чорний фон «перетікає» з чіпа на чіп
                            Capsule().fill(EmbarColors.ink)
                                .matchedGeometryEffect(id: "folderChipActive", in: ns)
                        } else {
                            Capsule().fill(EmbarColors.ink)
                        }
                    }
                }
            }
            // 0.10/3/1 = тінь пошукової пігулки: білі чіпи зливалися
            // з білим фоном (фідбек 2026-08-12)
            .shadow(color: .black.opacity(isActive ? 0 : 0.10), radius: 3, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // ×-бейдж: червоненький, вище-правіше — трошки виходить за межі
        // капсули (фідбек 2026-07-07). Бар дає чіпам верхній зазор,
        // щоб ScrollView не зрізав бейдж
        .overlay(alignment: .topTrailing) {
            if hovering, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(EmbarColors.danger))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}
