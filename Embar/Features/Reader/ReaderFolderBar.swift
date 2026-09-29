//
//  ReaderFolderBar.swift
//  Embar
//
//  Плаваючий бар папок полиці (SPEC §4.1; прототип renderFolderChips) —
//  дзеркалить NotesFolderBar, але папки тут рядкові (SPEC §11.7).
//  Лупа-пошук — крок 8 (поки заглушка) · «Всі» · чіпи папок · «+».
//

import SwiftUI

struct ReaderFolderBar: View {
    let folders: [String]
    let selected: String?
    @Binding var searchOpen: Bool
    @Binding var searchText: String
    let countFor: (String?) -> Int
    var onSelect: (String?) -> Void
    var onCreate: (String) -> Void
    var onDelete: (String) -> Void
    var morphNS: Namespace.ID
    /// У господаря (ReaderView): клік повз поле «Нова папка» його прибирає
    /// (фідбек 2026-08-12)
    @Binding var adding: Bool

    @State private var newName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Тригер перерендеру fade-градієнта при зміні «фону панелі» —
    /// ReaderView не спостерігає ThemeStore (фідбек 2026-07-19)
    @AppStorage("panelSurface") private var surfaceRaw = PanelSurface.warm.rawValue
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
        // Cmd+F міг відкрити пошук ззовні — сфокусувати поле
        .onChange(of: searchOpen) { _, open in
            if open { searchFocus = true }
        }
        // Скасування ззовні (ловець кліків) — почистити чернетку назви
        .onChange(of: adding) { _, adding in
            if !adding { newName = "" }
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
                .background(Capsule().fill(searchOpen ? EmbarColors.ink
                                                      : EmbarColors.surface.opacity(0.96)))
                // Тінь = FolderChip (0.10/3/1, фідбек 2026-08-12)
                .shadow(color: .black.opacity(searchOpen ? 0 : 0.10), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        TextField("", text: $searchText,
                  prompt: Text("Знайти блокнот...").foregroundStyle(EmbarColors.ink4))
            .textFieldStyle(.plain)
            .font(.emUI(12))
            .foregroundStyle(EmbarColors.ink)
            .focused($searchFocus)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .searchPillBackground()
            .onExitCommand { searchOpen = false; searchText = "" }
    }

    private var chips: some View {
        // Reader - щоб нове поле і пігулка ліміту не ховались за краєм
        // (фідбек 2026-09-04), як у барі папок нотаток
        ScrollViewReader { proxy in
        EdgeFadedHScroll {
            // Верхній/бічний зазор — простір для ×-бейджа видалення папки
            HStack(spacing: 5) {
                FolderChip(label: String(localized: "Всі", comment: "Чіп папки — усі блокноти"), count: countFor(nil),
                           isActive: selected == nil, morphNS: morphNS) {
                    onSelect(nil)
                }
                ForEach(folders, id: \.self) { folder in
                    FolderChip(label: folder, count: countFor(folder),
                               isActive: selected == folder, morphNS: morphNS,
                               onDelete: { onDelete(folder) }) {
                        onSelect(folder)
                    }
                }
                if adding {
                    NewChipField(placeholder: "Нова папка", text: $newName,
                                 onSubmit: finishAdd,
                                 onCancel: { settle { adding = false; newName = "" } },
                                 onLimitHit: { revealNewChip(proxy) })
                        .id(Self.newChipID)
                        .onAppear { revealNewChip(proxy) }
                } else {
                    FolderChip(label: "＋") { settle { adding = true } }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        }
    }

    private static let newChipID = "new-chip"

    /// Мʼякі рухи поля «Нова папка» (фідбек 2026-09-04), як у барі
    /// папок нотаток; Reduce Motion - миттєво
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
        let name = newName
        newName = ""
        settle {
            adding = false
            onCreate(name)
        }
    }
}
