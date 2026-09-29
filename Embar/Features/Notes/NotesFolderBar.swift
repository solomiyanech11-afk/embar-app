//
//  NotesFolderBar.swift
//  Embar
//
//  Плаваючий бар папок нотаток (SPEC §3.1) — дзеркалить walls bar Стіків:
//  лупа-пошук · «Всі» · чіпи папок (+лічильник) · «+». Прозорий флоут над
//  списком; порожні зони пропускають кліки, чіпи — непрозорі пігулки.
//

import SwiftUI

struct NotesFolderBar: View {
    let folders: [NoteFolder]
    @Binding var selectedFolderID: UUID?
    @Binding var searchOpen: Bool
    @Binding var searchText: String
    let countFor: (NoteFolder?) -> Int
    var onSelect: (UUID?) -> Void
    var onCreateFolder: (String) -> Void
    /// Видалення папки — ×-бейдж на ховері (фідбек 2026-07-07)
    var onDeleteFolder: (NoteFolder) -> Void = { _ in }
    var morphNS: Namespace.ID
    /// У господаря (NotesView): клік повз поле «Нова папка» його прибирає
    /// (фідбек 2026-08-12)
    @Binding var addingFolder: Bool

    @State private var newFolderName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocus: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            searchToggle
            if searchOpen {
                searchField
            } else {
                chips
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .bottomBarFade()
        // Скасування ззовні (ловець кліків) — почистити чернетку назви
        .onChange(of: addingFolder) { _, adding in
            if !adding { newFolderName = "" }
        }
    }

    private var searchToggle: some View {
        Button {
            searchOpen.toggle()
            if searchOpen { searchFocus = true } else { searchText = "" }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(searchOpen ? .white : EmbarColors.ink2)
                .frame(width: 28, height: 26)
                .background(Capsule().fill(searchOpen ? EmbarColors.ink : EmbarColors.surface.opacity(0.96)))
                // Тінь = FolderChip (0.10/3/1, фідбек 2026-08-12)
                .shadow(color: .black.opacity(searchOpen ? 0 : 0.10), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        TextField("Знайти нотатку...", text: $searchText)
            .textFieldStyle(.plain)
            .font(.emUI(12))
            .foregroundStyle(EmbarColors.ink)
            .focused($searchFocus)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .searchPillBackground()
            .onExitCommand { searchOpen = false; searchText = "" }
    }

    private var chips: some View {
        // Reader потрібен, щоб нове поле (і його пігулка ліміту) не
        // відкривались за правим краєм - бар прогортується до них сам
        // (фідбек 2026-09-04)
        ScrollViewReader { proxy in
        EdgeFadedHScroll {
            HStack(spacing: 5) {
                FolderChip(label: String(localized: "Всі", comment: "Чіп папки — усі нотатки"), count: countFor(nil),
                           isActive: selectedFolderID == nil, morphNS: morphNS) {
                    onSelect(nil)
                }
                ForEach(folders) { folder in
                    FolderChip(label: folder.name, count: countFor(folder),
                               isActive: selectedFolderID == folder.id, morphNS: morphNS,
                               onDelete: { onDeleteFolder(folder) }) {
                        onSelect(folder.id)
                    }
                }
                if addingFolder {
                    NewChipField(placeholder: "Нова папка", text: $newFolderName,
                                 onSubmit: finishAdd,
                                 onCancel: { settle { addingFolder = false; newFolderName = "" } },
                                 onLimitHit: { revealNewChip(proxy) })
                        .id(Self.newChipID)
                        .onAppear { revealNewChip(proxy) }
                } else {
                    FolderChip(label: "＋") { settle { addingFolder = true } }
                }
            }
            // Зазор для ×-бейджа видалення папки (щоб ScrollView не зрізав)
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        }
    }

    private static let newChipID = "new-chip"

    /// Рухи поля «Нова папка» - мʼякі (фідбек 2026-09-04: відкриття,
    /// ховання по Enter і догортування читались зарізко). Створення/
    /// відкриття - пряма дія на ряді, тож §7.2-A дозволяє; Reduce
    /// Motion - миттєво
    private func settle(_ change: () -> Void) {
        EmbarMotion.reorder(reduceMotion: reduceMotion, change)
    }

    /// Прогорнути бар до поля нової папки цілком (разом із пігулкою).
    /// Наступним тіком: у момент виклику поле/пігулка ще без розміру
    private func revealNewChip(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            settle { proxy.scrollTo(Self.newChipID, anchor: .trailing) }
        }
    }

    private func finishAdd() {
        let name = newFolderName
        newFolderName = ""
        settle {
            addingFolder = false
            onCreateFolder(name)
        }
    }
}
