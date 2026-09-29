//
//  FolderPickerList.swift
//  Embar
//
//  Спільний вміст попапу вибору папки — ОДИН вигляд для редактора нотаток
//  і блокнота рідера (консистентність — фідбек 2026-07-07). Показується
//  в нативному .popover (бульбашка з хвостиком): список опцій (вибрана —
//  жирніша, чорнилом) + поле «Нова папка...».
//

import SwiftUI

struct FolderPickerList: View {
    struct Option: Identifiable {
        let id: String
        let label: String
        let isSelected: Bool
        let select: () -> Void
    }

    let options: [Option]
    /// nil — без можливості створення
    var onCreate: ((String) -> Void)? = nil

    @State private var newName = ""

    /// Понад стільки опцій - список їде у фіксованій висоті (R3):
    /// раніше меню на десятки папок вилазило за екран і не згорталось
    private static let visibleRows = 10
    /// Висота ряду: текст 12pt (~15) + padding 5+5 + spacing 2
    private static let rowHeight: CGFloat = 27

    /// Спроба перевищити ліміт (R4): зайве вже зрізано, пігулка пояснює
    @State private var hitLimit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if options.count > Self.visibleRows {
                // Той самий патерн, що dropdown палітр у Settings:
                // фіксована висота + прихований індикатор. Пів зайвого
                // ряда визирає навмисно - видно, що список прокручується
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) { optionRows }
                }
                .scrollIndicators(.hidden)
                .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight + Self.rowHeight / 2)
            } else {
                optionRows
            }
            if let onCreate {
                Rectangle().fill(.black.opacity(0.06)).frame(height: 1)
                    .padding(.vertical, 3)
                TextField("", text: $newName,
                          prompt: Text("Нова папка...").foregroundStyle(EmbarColors.ink4))
                    .textFieldStyle(.plain)
                    .font(.emUI(12))
                    .foregroundStyle(EmbarColors.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .onSubmit {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        newName = ""
                        onCreate(name)
                    }
                    // Жорсткий блок ліміту (R4): понад 50 не пишеться
                    .onChange(of: newName) { _, newValue in
                        if FolderNameRule.exceeds(newValue) {
                            newName = FolderNameRule.clamped(newValue)
                            hitLimit = true
                        } else if newValue.count < FolderNameRule.maxLength {
                            hitLimit = false
                        }
                    }
                if hitLimit {
                    Text(FolderNameRule.message)
                        .font(.emUI(10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(EmbarColors.danger))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                }
            }
        }
        .padding(8)
        .frame(minWidth: 170)
    }

    /// Рядки опцій - одні й ті самі з кепом і без (R3)
    private var optionRows: some View {
        ForEach(options) { option in
            Button(action: option.select) {
                HStack {
                    Text(option.label.truncatedChip())
                        .font(.emUI(12, weight: option.isSelected ? .medium : .regular))
                        .foregroundStyle(option.isSelected ? EmbarColors.ink
                                                           : EmbarColors.ink2)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
