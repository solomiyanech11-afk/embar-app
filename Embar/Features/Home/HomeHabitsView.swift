//
//  HomeHabitsView.swift
//  Embar
//
//  Звички (SPEC §5.2): чекбокс (виконано сьогодні — derived від completions),
//  стрік 🔥, інлайн edit/delete. Скиду немає — новий день природно порожній.
//

import SwiftUI
import SwiftData

struct HomeHabitsView: View {
    @ObservedObject var home: HomeModel
    let palette: Palette
    @Binding var tab: HomeTab

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var toasts: ToastCenter
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]

    @State private var editingID: UUID?
    @State private var adding = false
    @State private var newText = ""

    private var habits: [Habit] { allHabits.filter { $0.deletedAt == nil } }

    private var filtered: [Habit] {
        habits.filter {
            let done = HomeService.isDone($0, on: home.todayAnchor)
            return tab == .todo ? !done : done
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionLabel("Звички")
            if filtered.isEmpty {
                if tab == .todo && habits.isEmpty {
                    // Короткий опис, що це і як живе (фідбек 2026-07-03)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Звички - маленькі щоденні ритуали.")
                            .font(.emDisplay(13, italic: true))
                        Text("Щоночі опівночі відмітки оновлюються, а стрік 🔥 рахує, скільки днів поспіль ти тримаєшся.")
                            .font(.emUI(11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(EmbarColors.ink3)
                    .padding(.vertical, 10)
                } else {
                    HomeEmptyLine(tab == .todo ? "Всі звички на сьогодні виконано"
                                               : "Тут зʼявлятимуться виконані звички.")
                }
            }
            ForEach(filtered) { habit in
                habitRow(habit)
            }
            if tab == .todo { addRow }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
    }

    private func habitRow(_ habit: Habit) -> some View {
        let streak = HomeService.streak(habit, today: home.todayAnchor)
        return HomeRowShell(
            text: habit.text,
            checked: HomeService.isDone(habit, on: home.todayAnchor),
            isEditing: editingID == habit.id,
            onToggle: { HomeService.toggleDone(habit, on: home.todayAnchor) }, // миттєво (§7.2-A)
            onStartEdit: { editingID = habit.id },
            onCommitEdit: { text in commitEdit(habit, text: text) },
            onCancelEdit: { if editingID == habit.id { editingID = nil } },
            onDelete: { deleteHabit(habit) }
        ) { _ in
            if streak > 0 {
                Text("🔥 \(streak)")
                    .font(.emUI(10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.accent)
            }
        }
    }

    @FocusState private var addFocus: Bool

    private var addRow: some View {
        Group {
            if adding {
                HStack(spacing: 11) {
                    HomeCheckbox()
                    TextField("нова звичка…", text: $newText)
                        .textFieldStyle(.plain).font(.emUI(13)).foregroundStyle(EmbarColors.ink)
                        .focused($addFocus)
                        .onSubmit(commitAdd)
                        .onExitCommand { adding = false; newText = "" }
                        .onChange(of: addFocus) { _, focused in
                            if !focused, newText.trimmingCharacters(in: .whitespaces).isEmpty {
                                adding = false
                            }
                        }
                }
                .padding(.horizontal, 2).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.025)))
            } else {
                Button { adding = true; newText = ""; Task { addFocus = true } } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .light))
                            .foregroundStyle(EmbarColors.ink3).frame(width: 17, height: 17)
                        Text("нова звичка")
                            .font(.emDisplay(12.5, italic: true)).foregroundStyle(EmbarColors.ink3)
                        Spacer()
                    }
                    .padding(.horizontal, 2).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitEdit(_ habit: Habit, text: String) {
        // Guard від застарілого blur/submit (як тудушки)
        guard editingID == habit.id else { return }
        editingID = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { deleteHabit(habit) } else { habit.text = t; habit.updatedAt = .now }
    }

    private func commitAdd() {
        // Enter = зберегти і вийти зі стану вводу (як тудушки)
        HomeService.addHabit(newText, in: context)
        newText = ""
        adding = false
    }

    private func deleteHabit(_ habit: Habit) {
        HomeService.softDelete(habit) // оновлення списку — миттєве (§7.2-A)
        toasts.showUndo(message: "Звичку видалено") {
            HomeService.undoDelete(habit)
        }
    }
}
