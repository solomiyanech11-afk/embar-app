//
//  HomeListsView.swift
//  Embar
//
//  Списки Home (SPEC §5.2): таби «До зробити N / Виконано N» + тудушки з
//  каруселлю тек. Звички — крок 8 (додаються в цей же контейнер).
//

import SwiftUI
import SwiftData

enum HomeTab { case todo, done }

struct HomeListsView: View {
    @ObservedObject var home: HomeModel
    let palette: Palette
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var toasts: ToastCenter

    @Query(sort: \Todo.createdAt) private var allTodos: [Todo]
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]
    @Query(sort: \HomeTag.createdAt) private var allCustomTags: [HomeTag]

    @Binding var tab: HomeTab
    @State private var folderIdx = 0
    /// Напрям гортання тек: 1 = вперед (сторінка в'їжджає справа), -1 = назад
    @State private var folderDirection = 1

    // Інлайн-редагування / додавання (буфер редагування — усередині TodoRow)
    @State private var editingID: UUID?
    @State private var addingInFolder: Int?
    @State private var newText = ""
    @State private var newTag: String?
    @State private var newTagPickerOpen = false
    @State private var tagPickerTodoID: UUID?
    @FocusState private var addFocus: Bool

    private var todos: [Todo] { allTodos.filter { $0.deletedAt == nil } }
    private var customTags: [HomeTag] { allCustomTags.filter { $0.deletedAt == nil } }
    /// Теки: nil = «Всі», далі — ЛИШЕ створені користувачем теги (жодних
    /// дефолтних робота/сім'я/дім). Тег стає текою, коли його додають
    private var folders: [String?] { [nil] + customTags.map(\.name) }
    /// folderIdx, захищений від зникнення тега (delete/sync/undo): без clamp
    /// folders[folderIdx] крашив би index-out-of-range (review, латентний)
    private var safeFolderIdx: Int { min(folderIdx, max(folders.count - 1, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionLabel("Тудушки")
            card
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Картка з каруселлю

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            carousel
        }
    }

    private var cardHeader: some View {
        HStack {
            Text(folderTitle).font(.emUI(13, weight: .medium)).foregroundStyle(EmbarColors.ink)
            Text("\(filteredTodos(safeFolderIdx).count)")
                .font(.emUI(11).monospacedDigit()).foregroundStyle(EmbarColors.ink3)
            Spacer()
            // Крапки лише коли є теки крім «Всі» (тобто створено теги)
            if folders.count > 1 {
                HStack(spacing: 6) {
                    ForEach(folders.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == folderIdx ? EmbarColors.ink : Color.black.opacity(0.18))
                            .frame(width: i == folderIdx ? 18 : 5, height: 5)
                            .onTapGesture { switchFolder(to: i) }
                    }
                }
                // Морф крапок: активна «перетікає» в пігулку (виняток §7.2-A)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: folderIdx)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 8)
    }

    /// Показуємо активну теку напряму (повна ширина); зміна теки — плавний
    /// кросфейд. Без GeometryReader-виміру, який раніше застрягав на 300pt
    /// і робив рядки вужчими за панель.
    /// Сторінки тек гортаються «карткою» (виняток §7.2-A). Через SlideInPage
    /// (onAppear-в'їзд), НЕ .transition — той при .id-swap усередині
    /// ScrollView шторки не спрацьовував і фліп був no-op (code review)
    private var carousel: some View {
        SlideInPage(direction: folderDirection) {
            folderPage(safeFolderIdx)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(folderIdx)
    }

    private func switchFolder(to i: Int) {
        guard i != folderIdx else { return }
        folderDirection = i > folderIdx ? 1 : -1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            folderIdx = i // spring живить морф крапок; в'їзд сторінки — свій
        }
    }

    private func folderPage(_ idx: Int) -> some View {
        let items = filteredTodos(idx)
        return VStack(spacing: 0) {
            // «До зробити»: порожня тека БЕЗ тексту — сама кнопка додавання
            // (рішення 2026-07-04); текст лише у порожньому «Виконано»
            if items.isEmpty && tab == .done {
                HomeEmptyLine("Тут зʼявлятиметься зроблене.")
            }
            ForEach(items) { todo in todoRow(todo) }
            if tab == .todo { addRow(idx) }
        }
    }

    // MARK: - Рядок

    private func todoRow(_ todo: Todo) -> some View {
        TodoRow(
            todo: todo,
            isEditing: editingID == todo.id,
            palette: palette,
            customTags: customTags,
            onToggle: { HomeService.toggleDone(todo) }, // миттєво (§7.2-A)
            onStartEdit: { editingID = todo.id },
            onCommitEdit: { text in commitEdit(todo, text: text) },
            onCancelEdit: { if editingID == todo.id { editingID = nil } },
            onOpenTagPicker: { tagPickerTodoID = todo.id },
            onDelete: { deleteTodo(todo) },
            tagPickerBinding: Binding(
                get: { tagPickerTodoID == todo.id },
                set: { if !$0 { tagPickerTodoID = nil } }
            ),
            onSelectTag: { todo.tagName = $0; todo.updatedAt = .now; tagPickerTodoID = nil },
            onCreateTag: { name in
                if let t = HomeService.createCustomTag(name, existing: customTags, in: context) {
                    todo.tagName = t.name
                }
                tagPickerTodoID = nil
            }
        )
    }

    private func addRow(_ idx: Int) -> some View {
        Group {
            if addingInFolder == idx {
                typingRow(idx)
            } else {
                Button {
                    addingInFolder = idx
                    newText = ""
                    newTag = folders[idx] // тека одразу дає свій тег
                    Task { addFocus = true } // авто-фокус після появи поля
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .light))
                            .foregroundStyle(EmbarColors.ink3).frame(width: 17, height: 17)
                        Text(idx == 0 ? "нова тудушка" : "нова - \(folders[idx] ?? "")")
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

    /// Рядок вводу нової тудушки: як звичайний рядок «під мишкою» — з видимими
    /// «+ тег» і смітником (фідбек 2026-07-03). Enter створює і лишає поле
    /// відкритим для наступної; Esc/смітник/блюр-порожнім — закривають.
    private func typingRow(_ idx: Int) -> some View {
        HStack(spacing: 11) {
            HomeCheckbox()
            TextField("нова тудушка…", text: $newText)
                .textFieldStyle(.plain).font(.emUI(13)).foregroundStyle(EmbarColors.ink)
                .focused($addFocus)
                .onSubmit { commitAdd(idx) }
                .onExitCommand(perform: cancelAdd)
                .onChange(of: addFocus) { _, focused in
                    // Блюр з порожнім текстом → закрити (не коли відкрито пікер тега)
                    if !focused, !newTagPickerOpen,
                       newText.trimmingCharacters(in: .whitespaces).isEmpty {
                        cancelAdd()
                    }
                }
            Spacer(minLength: 6)
            Button { newTagPickerOpen = true } label: { pendingTagPill }
                .buttonStyle(.plain)
                .popover(isPresented: $newTagPickerOpen, arrowEdge: .bottom) {
                    HomeTagPicker(
                        selected: newTag, customTags: customTags, palette: palette,
                        onSelect: { newTag = $0; newTagPickerOpen = false; addFocus = true },
                        onCreate: { name in
                            if let t = HomeService.createCustomTag(name, existing: customTags, in: context) {
                                newTag = t.name
                            }
                            newTagPickerOpen = false
                            addFocus = true
                        }
                    )
                }
            Button(action: cancelAdd) {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(EmbarColors.ink3)
                    .padding(2).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.025)))
    }

    @ViewBuilder private var pendingTagPill: some View {
        if let tag = newTag {
            HomeTagPill(label: tag, palette: palette)
        } else {
            HomeTagPill(label: String(localized: "+ тег", comment: "Кнопка додати тег до тудушки"), palette: palette, colored: false)
        }
    }

    private func cancelAdd() {
        addingInFolder = nil
        newText = ""
        newTag = nil
        newTagPickerOpen = false
    }

    // MARK: - Дані

    private var folderTitle: String {
        switch safeFolderIdx {
        case 0: return String(localized: "Всі", comment: "Тека каруселі тудушок — усі")
        default:
            let t = folders[safeFolderIdx] ?? ""
            return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    private func filteredTodos(_ idx: Int) -> [Todo] {
        let folder = folders[idx]
        return todos.filter { t in
            (folder == nil || t.tagName == folder) && (tab == .todo ? !t.done : t.done)
        }
    }

    private func commitEdit(_ todo: Todo, text: String) {
        // Guard від застарілого blur-коміту: якщо редагування вже перейшло
        // на інший рядок (або закрите), пізній submit/blur цього рядка — no-op
        guard editingID == todo.id else { return }
        editingID = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { deleteTodo(todo) } else { todo.text = t; todo.updatedAt = .now }
    }

    private func commitAdd(_ idx: Int) {
        // Enter = зберегти і вийти зі стану вводу (фідбек 2026-07-04);
        // наступну — знову через «+ нова тудушка»
        HomeService.addTodo(newText, tag: newTag, in: context)
        cancelAdd()
    }

    private func deleteTodo(_ todo: Todo) {
        HomeService.softDelete(todo) // оновлення списку — миттєве (§7.2-A)
        toasts.showUndo(message: "Тудушку видалено") {
            HomeService.undoDelete(todo)
        }
    }
}

// MARK: - Секція-лейбл

struct HomeSectionLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        // .textCase, а не .uppercased(): регістр — уже до перекладу (i18n)
        Text(text)
            .textCase(.uppercase)
            .font(.emUI(10, weight: .medium)).tracking(1.4)
            .foregroundStyle(EmbarColors.ink3)
            .padding(.top, 4).padding(.bottom, 8)
    }
}

/// Порожній стан списку — приглушений рядок у тоні бренду (SPEC §8.1.1)
struct HomeEmptyLine: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.emDisplay(13, italic: true))
            .foregroundStyle(EmbarColors.ink3)
            .padding(.vertical, 10)
    }
}
