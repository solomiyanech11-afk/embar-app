//
//  ReaderView.swift
//  Embar
//
//  Поверхня «Рідер» (SPEC §4.1): полиця блокнотів-джерел. Editorial-сітка
//  груп tall+квадрати, плитка «+ Новий блокнот» завжди після карток.
//  Блокнот-overlay — крок 3; бар папок і пошук — кроки 7–8.
//

import SwiftUI
import SwiftData

struct ReaderView: View {
    @ObservedObject var model: ReaderModel

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var toasts: ToastCenter
    @Query(sort: \ReaderBook.updatedAt, order: .reverse) private var allBooks: [ReaderBook]
    @Namespace private var folderChipNS
    /// Папка, для якої відкрито віконце-питання видалення
    @State private var folderToDelete: String?
    /// Поле «Нова папка» в барі: стан тут, щоб клік повз (ловець на всю
    /// поверхню) міг його прибрати (фідбек 2026-08-12)
    @State private var addingFolder = false

    private var liveBooks: [ReaderBook] { allBooks.filter { $0.deletedAt == nil } }

    /// Полиця: фільтр папки + пошук (назва/джерело/текст записів/автор —
    /// прототип renderReaderShelf)
    private var books: [ReaderBook] {
        var result = liveBooks
        if let folder = model.selectedFolder {
            result = result.filter { $0.folderName == folder }
        }
        let query = model.shelfSearchText
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard model.shelfSearchOpen, !query.isEmpty else { return result }
        return result.filter { book in
            if book.title.lowercased().contains(query) { return true }
            if (book.sources ?? []).contains(where: {
                $0.deletedAt == nil
                    && ($0.url.lowercased().contains(query)
                        || $0.label.lowercased().contains(query)) }) { return true }
            return (book.entries ?? []).contains { entry in
                entry.deletedAt == nil
                    && (entry.text.lowercased().contains(query)
                        || (entry.author ?? "").lowercased().contains(query))
            }
        }
    }

    var body: some View {
        let items = books
        ScrollView {
            Color.clear.frame(height: 0).onAppear {
                // ⚠️ Debug-стенд (GlassLab): `-GlassShotOpenBook YES` —
                // одразу відкрити перший блокнот для self-скріншота
                if EmbarDefaults.store.bool(forKey: "GlassShotOpenBook"),
                   let first = items.first {
                    model.open(first)
                }
            }
            VStack(spacing: 8) {
                shelf(items)
                if items.isEmpty {
                    if model.shelfSearchOpen, !model.shelfSearchText.isEmpty {
                        // Порожній результат пошуку (прототип, 13px)
                        Text("Нічого не знайдено.")
                            .font(.emUI(13))
                            .foregroundStyle(EmbarColors.ink3)
                            .padding(.top, 30)
                    } else {
                        EmptyStateText(line1: "Вивчаєш щось цікаве?",
                                       line2: "Створи перший блокнот, щоб нічого не забути.")
                            .padding(.top, 90)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 72)    // під скляним рядком + повітря (як у стіках)
            .padding(.bottom, 48) // місце під плаваючим баром папок
            // Каскад полиці — ЛИШЕ на зміну папки (§7.2-A, як у нотатках)
            .id(model.selectedFolder ?? "all")
        }
        .scrollIndicators(.hidden)
        // Клік повз поле «Нова папка» = передумав. Ловець лежить ПІД
        // баром папок (там і пошук), тож поля, що крадуть фокус, він не
        // накриває — спільний модифікатор, як у Стіках і Нотатках
        .dismissOnTapOutside(addingFolder) { addingFolder = false }
        // Верхня зона як у стіках/нотатках: вище верхнього краю рядка —
        // суцільний колір панелі (15pt = top-паддінг), далі розчинення
        // йде вже ПІД склом
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(EmbarColors.surface).frame(height: 15)
                LinearGradient(colors: [EmbarColors.surface,
                                        EmbarColors.surface.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
            }
            .allowsHitTesting(false)
        }
        // Рядок «+ Новий блокнот» (P2.34) — та сама оболонка й місце,
        // що композери стіків і нотаток
        .overlay(alignment: .top) {
            ReaderNewBookRow { createBook(count: items.count) }
        }
        .overlay(alignment: .bottom) { folderBar }
        // Під віконцем - світлий блюр як при розгорнутому стіку
        .dialogDimmed(folderToDelete != nil)
        // Віконце-питання видалення папки (фідбек 2026-07-07):
        // контейнер має два сценарії — сам чи разом із вмістом
        .overlay {
            if let name = folderToDelete {
                ConfirmDeleteDialog(
                    title: "Видалити папку «\(name.truncatedChip())»?",
                    keepLabel: "Лише папку - блокноти залишаться",
                    purgeLabel: "Разом із блокнотами",
                    onKeep: { removeFolder(name, purgeBooks: false) },
                    onPurge: { removeFolder(name, purgeBooks: true) },
                    onCancel: { folderToDelete = nil })
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: folderToDelete)
    }

    private func removeFolder(_ name: String, purgeBooks: Bool) {
        folderToDelete = nil
        let affected = liveBooks.filter { $0.folderName == name }
        ReaderService.removeFolder(name)
        if model.selectedFolder == name { switchFolder(to: nil) }
        withAnimation {
            for book in affected {
                if purgeBooks { ReaderService.softDeleteBook(book) }
                else { ReaderService.setFolder(nil, for: book) }
            }
        }
        toasts.showUndo(message: purgeBooks ? "Папку і блокноти видалено"
                                            : "Папку видалено") {
            _ = ReaderService.addFolder(name)
            withAnimation {
                for book in affected {
                    if purgeBooks { ReaderService.undoDeleteBook(book) }
                    else { ReaderService.setFolder(name, for: book) }
                }
            }
        }
    }

    // MARK: - Бар папок (плаваючий, крок 7)

    private var folderBar: some View {
        ReaderFolderBar(
            folders: ReaderService.folders(including: liveBooks),
            selected: model.selectedFolder,
            searchOpen: $model.shelfSearchOpen,
            searchText: $model.shelfSearchText,
            countFor: countFor,
            onSelect: switchFolder,
            onCreate: { name in
                guard ProGate.allowCreate() else { return } // режим читання
                if let clean = ReaderService.addFolder(name) {
                    switchFolder(to: clean)
                }
            },
            onDelete: { folderToDelete = $0 },
            morphNS: folderChipNS,
            adding: $addingFolder
        )
    }

    private func switchFolder(to folder: String?) {
        guard folder != model.selectedFolder else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.selectedFolder = folder
        }
    }

    private func countFor(_ folder: String?) -> Int {
        guard let folder else { return liveBooks.count }
        return liveBooks.filter { $0.folderName == folder }.count
    }

    // MARK: - Сітка полиці

    @ViewBuilder private func shelf(_ items: [ReaderBook]) -> some View {
        ForEach(Array(ReaderShelfLayout.groups(count: items.count).enumerated()),
                id: \.offset) { pair in
            CascadeReveal(order: pair.offset) {
                groupView(pair.element, items: items)
            }
        }
    }

    @ViewBuilder private func groupView(_ group: ReaderShelfLayout.Group,
                                        items: [ReaderBook]) -> some View {
        switch group {
        case .full(let index):
            card(items[index], .tall)

        case .pair(let tall, let square, let tallLeft):
            HStack(alignment: .top, spacing: 8) {
                if tallLeft {
                    card(items[tall], .tall)
                    card(items[square], .square)
                } else {
                    card(items[square], .square)
                    card(items[tall], .tall)
                }
            }

        case .trio(let tall, let squares, let tallLeft):
            HStack(alignment: .top, spacing: 8) {
                if tallLeft {
                    card(items[tall], .tall)
                    squareColumn(squares, items: items)
                } else {
                    squareColumn(squares, items: items)
                    card(items[tall], .tall)
                }
            }
        }
    }

    private func squareColumn(_ indices: [Int], items: [ReaderBook]) -> some View {
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { card(items[$0], .square) }
        }
    }

    private func card(_ book: ReaderBook, _ shape: ReaderBookCard.CardShape) -> some View {
        ReaderBookCard(book: book, shape: shape) { model.open(book) }
    }

    // MARK: - Створення

    private func createBook(count: Int) {
        guard ProGate.allowCreate() else { return } // режим читання
        // Новий блокнот успадковує вибрану папку (прототип) і одразу
        // відкривається; назва - заповнювач, фокус - у назві з виділеним
        // заповнювачем, набір замінює його (фідбек 2026-09-04,
        // SPEC §15.72в)
        let book = ReaderService.createBook(folderName: model.selectedFolder,
                                            existingCount: count, in: context)
        model.openNew(book)
    }
}
