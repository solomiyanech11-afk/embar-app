//
//  ReaderModel.swift
//  Embar
//
//  Спільний стан поверхні «Рідер» на рівні панелі (як NotesModel):
//  блокнот-overlay накриває всю панель, тому відкрита книга живе тут.
//

import SwiftUI
import Combine

@MainActor
final class ReaderModel: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    /// Відкритий блокнот (nil = полиця). Overlay рендерить ContentView
    @Published var openBook: ReaderBook?
    /// Вибрана папка полиці (nil = «Всі») — живе на рівні панелі,
    /// як currentReaderFolder у прототипі
    @Published var selectedFolder: String?
    /// goToReaderEntry: запис, до якого скролимо зі спалахом після
    /// відкриття блокнота (SPEC §12.3)
    @Published var pendingFlashEntryID: UUID?

    // Пошук (SPEC §4.1/§4.3, крок 8). Живе тут, щоб Cmd+F із ContentView
    // міг маршрутизувати: блокнот відкритий → пошук у записах, ні → полиця
    @Published var shelfSearchOpen = false
    @Published var shelfSearchText = ""
    @Published var notebookSearchOpen = false
    @Published var notebookSearchText = ""

    /// Щойно створений блокнот відкривається з фокусом у назві:
    /// заповнювач виділено цілим, набір замінює його (фідбек 2026-09-04;
    /// безпечно після P2.24 - select-all-мигання гаситься на панелі)
    @Published var focusTitleOnOpen = false

    func open(_ book: ReaderBook) {
        resetNotebookSearch() // новий блокнот — чистий пошук (прототип)
        openBook = book
    }

    func openNew(_ book: ReaderBook) {
        resetNotebookSearch()
        focusTitleOnOpen = true
        openBook = book
    }

    func close() {
        openBook = nil
        focusTitleOnOpen = false
        resetNotebookSearch()
    }

    /// Cmd+F: у блокноті — пошук записів, на полиці — пошук блокнотів
    func toggleContextualSearch() {
        if openBook != nil {
            notebookSearchOpen.toggle()
            if !notebookSearchOpen { notebookSearchText = "" }
        } else {
            shelfSearchOpen.toggle()
            if !shelfSearchOpen { shelfSearchText = "" }
        }
    }

    private func resetNotebookSearch() {
        notebookSearchOpen = false
        notebookSearchText = ""
    }
}
