//
//  NotesModel.swift
//  Embar
//
//  Спільний стан поверхні «Нотатки», піднятий на рівень панелі (як HomeModel),
//  щоб повноекранний редактор-оверлей накривав УСЮ панель — хедер, таби,
//  футер — а не лише область списку.
//

import SwiftUI
import Combine

@MainActor
final class NotesModel: ObservableObject {
    /// Вибрана папка у folder bar (nil = «Всі»)
    @Published var selectedFolderID: UUID?
    /// Розгорнутий пошук (лупа) + запит
    @Published var searchOpen = false
    @Published var searchText = ""

    /// Навігаційний стек редактора: дитина → батько → список.
    /// Порожній = редактор закритий. `.last` — відкрита нотатка.
    @Published var editorStack: [Note] = []
    var editingNote: Note? { editorStack.last }
    var isEditing: Bool { !editorStack.isEmpty }

    /// Відкрити нотатку (з чистого списку)
    func open(_ note: Note) { editorStack = [note] }
    /// Провалитися в іншу нотатку (клік по чіпу-згадці / backlink) —
    /// «назад» повертає
    func push(_ note: Note) { editorStack.append(note) }
    /// Крок назад по стеку; на кореневому рівні — закриває редактор
    func back() { if !editorStack.isEmpty { editorStack.removeLast() } }
    /// Повністю закрити редактор
    func close() { editorStack.removeAll() }

    // MARK: - Кеш списку (F5, пункт 4)

    private let sliceEngine = NoteListSliceEngine()
    /// НЕ @Published: перемальовку і так тягне мутація (@Query)
    private var sliceDirty = true
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .embarNoteMutated, object: nil,
                               queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let target = note.object as? Note,
                          !self.sliceDirty else { return }
                    self.sliceEngine.update(target)
                }
            },
            center.addObserver(forName: .embarNotesBulkChanged, object: nil,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sliceDirty = true }
            },
        ]
    }

    nonisolated deinit { // захист від міни ізольованого deinit — див. CLAUDE.md
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Зріз ПАПКИ (членство + порядок + лічильники). Пошук накладає
    /// NotesView зверху: він порядку не міняє, а тримати title/content у
    /// зліпках було б дорого (див. шапку NoteListSlice.swift).
    /// ❗ `all` — @autoclosure: сам доступ до масиву @Query після мутації
    /// матеріалізує всі обʼєкти наново (~275 мс на 5000), тож кеш-хіт не
    /// сміє його торкатись
    func slice(all: @autoclosure () -> [Note]) -> NoteListSlice {
        if sliceDirty || sliceEngine.folderID != .some(selectedFolderID) {
            let materialized = all()
            #if DEBUG
            let probeStart = PerfProbe.isActive ? CFAbsoluteTimeGetCurrent() : 0
            #endif
            sliceEngine.rebuild(all: materialized, folderID: selectedFolderID)
            sliceDirty = false
            sliceDivergedOnce = false // свіжа збірка — старі гонки забуто
            #if DEBUG
            if PerfProbe.isActive {
                PerfProbe.shared.record("notes.sorted(\(materialized.count) всього)",
                                        seconds: CFAbsoluteTimeGetCurrent() - probeStart)
            }
            #endif
        } else {
            #if DEBUG
            if PerfProbe.isActive {
                PerfProbe.shared.record("notes.sorted.cached", seconds: 0)
            }
            // Запобіжник розходження — той самий, що для стіни (план F5):
            // умова ЗЗОВНІ, інакше all() матеріалізувався б і в релізі
            if SandboxEnvironment.isActive, !PerfProbe.isActive {
                verifySliceInSandbox(all: all())
            }
            #endif
        }
        return sliceEngine.slice
    }

    /// Розходження, побачене на попередньому рендері. Падаємо лише коли
    /// воно ПОВТОРИЛОСЬ (2026-09-01): кеш патчиться синхронно зі вставкою,
    /// а масив @Query наздоганяє на такт пізніше — рендер, спричинений не
    /// самим @Query (напр. відкриттям редактора одразу після створення
    /// нотатки), бачить кеш «попереду» еталона. Це гонка на один кадр, не
    /// протухлий кеш: справжній стейл розходиться стабільно і впаде на
    /// наступному ж рендері
    private var sliceDivergedOnce = false

    private func verifySliceInSandbox(all: [Note]) {
        let reference = NoteListSliceEngine.computeReference(
            all: all, folderID: selectedFolderID)
        guard let divergence = sliceEngine.divergence(from: reference) else {
            sliceDivergedOnce = false
            return
        }
        guard sliceDivergedOnce else {
            sliceDivergedOnce = true
            return
        }
        fatalError("""
            Кеш списку нотаток розійшовся з перерахунком ДВІЧІ ПОСПІЛЬ: \
            \(divergence). Папка: \(selectedFolderID?.uuidString ?? "всі"). \
            Найімовірніше, якийсь шлях мутації нотаток не викликає \
            NoteMutation.changed/bulkChanged.
            """)
    }
}
