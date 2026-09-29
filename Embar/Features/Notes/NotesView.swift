//
//  NotesView.swift
//  Embar
//
//  Поверхня «Нотатки» (SPEC §3.1): композер + список карток + плаваючий бар
//  папок з пошуком. Повноекранний редактор — оверлей на рівні ContentView.
//

import SwiftUI
import SwiftData

struct NotesView: View {
    @ObservedObject var model: NotesModel

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var home: HomeModel

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \NoteFolder.createdAt) private var allFolders: [NoteFolder]

    @Namespace private var folderChipNS
    /// Каскад грає лише вікно після зміни папки (перф 2026-08-16: у
    /// LazyVStack onAppear приходить і при скролі — хвиля програвалась би
    /// щоразу, коли картки повертаються у вʼюпорт)
    @State private var cascadeArmed = true
    @State private var cascadeGeneration = 0
    /// Папка, для якої відкрито віконце-питання видалення (фідбек 2026-07-07)
    @State private var folderToDelete: NoteFolder?
    /// Нотатка, що прибуває на нове місце після піна (P2.11, той самий
    /// шлях, що pinArrivalID стіни стіків): анімована перескладка
    /// LazyVStack розсинхронювала текст і фон картки — текст зʼявлявся
    /// на новому місці одразу, білий фон доїжджав слідом. Тепер список
    /// перескладається миттєво, а сама картка проявляється (ArrivalReveal)
    @State private var pinArrivalID: UUID?
    /// Ховер карток озброєний. Після видалення/undo сусіди анімовано
    /// закривають дірку — на цей час ховер вимкнено, щоб кнопки не
    /// «переїжджали» на картку, що підпливла під курсор (P2.12); свої
    /// кнопки вона покаже з першого руху миші після перестановки
    @State private var hoverArmed = true
    @State private var hoverArmGeneration = 0
    /// Поле «Нова папка» в барі: стан тут, щоб клік повз (ловець на всю
    /// поверхню) міг його прибрати (фідбек 2026-08-12)
    @State private var addingFolder = false

    private var folders: [NoteFolder] { allFolders.filter { $0.deletedAt == nil } }
    private var selectedFolder: NoteFolder? { folders.first { $0.id == model.selectedFolderID } }

    private var liveNotes: [Note] { allNotes.filter { $0.deletedAt == nil } }

    /// Зріз папки (членство + порядок + лічильники) живе в кеші NotesModel
    /// (F5.4, 2026-08-28): раніше фільтр+сортування ганялись на КОЖЕН body —
    /// 447 мс при відкритті на 5000 і ще по ~275 мс просто під час скролу.
    /// Пошук накладається ЗВЕРХУ на вже відсортований масив: він порядку не
    /// міняє, а тримати title/content у зліпках кеша було б дорого
    private func makeSlice() -> NoteListSlice {
        model.slice(all: allNotes)
    }

    private func searched(_ slice: NoteListSlice) -> [Note] {
        let q = model.searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return slice.items }
        // range(of:.caseInsensitive) замість lowercased().contains:
        // той алокував копію всього тіла КОЖНОЇ нотатки на кожну
        // клавішу пошуку (перф-фікс 2026-08-16)
        return slice.items.filter { note in
            note.title.range(of: q, options: .caseInsensitive) != nil
                || note.content.range(of: q, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        // Один зріз за рендер (перевірка порожнечі + список + лічильники)
        let slice = makeSlice()
        let items = searched(slice)
        // Той самий принцип, що відполірували в Стіках (2026-07-20):
        // скрол на всю поверхню, поле — левітуюче скло НАД списком,
        // нотатки прогортуються під нього і розчиняються у fade-зоні
        ScrollView {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list(items)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 72)    // під скляним полем + повітря (як у стіках)
            .padding(.bottom, 40) // місце під плаваючим баром папок
            // Каскад — ЛИШЕ на зміну папки (§7.2-A). Пошук фільтрує
            // миттєво: searchText у ключі перезбирав увесь список і
            // програвав каскад на КОЖНУ клавішу (code review #3)
            .id(model.selectedFolderID?.uuidString ?? "all")
        }
        .scrollIndicators(.hidden)
        // Клік у ПОРОЖНЄ місце поверхні скидає пошук і ховає поле (P2.16).
        // Саме .background, а не ловець-оверлей: картки мають лишатись
        // клікабельними (відкриття нотатки пошук не чіпає) — до підкладки
        // долітають лише кліки повз них
        .background {
            if model.searchOpen {
                Color.black.opacity(0.001).onTapGesture {
                    model.searchOpen = false
                    model.searchText = ""
                }
            }
        }
        // Клік повз поле «Нова папка» = передумав. ❗ Ловець чіпляємо
        // ПЕРШИМ, щоб він лежав ПІД склом композера і баром папок:
        // раніше він був вище і з'їдав перший клік у композер
        // (ревʼю 2026-08-18, знахідка 4)
        .dismissOnTapOutside(addingFolder) { addingFolder = false }
        .onAppear(perform: armCascade)
        .onChange(of: model.selectedFolderID) { _, _ in armCascade() }
        // Верхня зона як у стіках: вище верхнього краю поля — суцільний
        // колір панелі (15pt = top-паддінг поля), далі розчинення йде
        // вже ПІД склом
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
        .overlay(alignment: .top) { composer }
        .overlay(alignment: .bottom) { folderBar(slice) }
        // Під віконцем - світлий блюр як при розгорнутому стіку
        .dialogDimmed(folderToDelete != nil)
        // Віконце-питання видалення папки: лише папку чи разом із нотатками
        .overlay {
            if let folder = folderToDelete {
                ConfirmDeleteDialog(
                    title: "Видалити папку «\(folder.name.truncatedChip())»?",
                    keepLabel: "Лише папку - нотатки залишаться",
                    purgeLabel: "Разом із нотатками",
                    onKeep: { removeFolder(folder, purgeNotes: false) },
                    onPurge: { removeFolder(folder, purgeNotes: true) },
                    onCancel: { folderToDelete = nil })
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: folderToDelete?.id)
    }

    private func removeFolder(_ folder: NoteFolder, purgeNotes: Bool) {
        folderToDelete = nil
        let affected = liveNotes.filter { $0.folder?.id == folder.id }
        if model.selectedFolderID == folder.id { switchFolder(to: nil) }
        settle {
            folder.deletedAt = .now
            for note in affected {
                if purgeNotes { NoteService.softDelete(note) }
                else { NoteService.setFolder(nil, for: note) }
            }
            // Страховка поверх точкових патчів: міняється і сама папка
            // (той самий підхід, що removeWall на стіні)
            NoteMutation.bulkChanged()
        }
        toasts.showUndo(message: purgeNotes ? "Папку і нотатки видалено"
                                            : "Папку видалено") {
            settle {
                folder.deletedAt = nil
                for note in affected {
                    if purgeNotes { NoteService.undoDelete(note) }
                    else { NoteService.setFolder(folder, for: note) }
                }
                NoteMutation.bulkChanged() // страховка, як у прямого шляху
            }
        }
    }

    // MARK: - Композер

    private var composer: some View {
        // Чернетка живе ВСЕРЕДИНІ NotesQuickInput: кожен символ раніше
        // мутував @State цієї вьюхи і пере-рендерив увесь список — на
        // тисячах нотаток друк заїкався (перф-фікс 2026-08-16, як у стіках)
        NotesQuickInput(
            // Не красти фокус, коли зверху редактор, шторка чи
            // віконце-питання видалення папки
            autoFocus: model.editingNote == nil && !home.isOpen
                && folderToDelete == nil
        ) { title in
            // Enter створює нотатку в поточній папці й відкриває редактор (SPEC §3.1)
            let note = NoteService.add(title: title, folder: selectedFolder, in: context)
            model.open(note)
        }
    }

    // MARK: - Список

    /// Увімкнути каскад на ~0.7 с після зміни папки (див. cascadeArmed)
    private func armCascade() {
        cascadeArmed = true
        cascadeGeneration += 1
        let generation = cascadeGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if cascadeGeneration == generation { cascadeArmed = false }
        }
    }

    private func list(_ items: [Note]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                CascadeReveal(order: pair.offset, animated: cascadeArmed) {
                    ArrivalReveal(active: pinArrivalID == pair.element.id) {
                        NoteCard(
                            note: pair.element,
                            palette: theme.current,
                            onOpen: { model.open(pair.element) },
                            // Пін БЕЗ анімованої перескладки (P2.11, як
                            // pinWithArrival стіни стіків): анімований
                            // переїзд у LazyVStack розсинхронював текст
                            // і фон картки
                            onTogglePin: { pinWithArrival(pair.element) },
                            onDelete: { deleteWithUndo(pair.element) },
                            hoverEnabled: hoverArmed
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)   // як внутрішній відступ стіни стіків
        .padding(.bottom, 20)
    }

    /// Перестановка списку — крива EmbarMotion.settle; з Reduce Motion
    /// миттєво (§7.2-A)
    private func settle(_ change: () -> Void) {
        EmbarMotion.reorder(reduceMotion: reduceMotion, change)
    }

    /// Пін без анімованої перескладки (P2.11): список стає на нові місця
    /// миттєво, а запінена картка тихо проявляється на новій позиції —
    /// той самий рух, що pinWithArrival на стіні стіків
    private func pinWithArrival(_ note: Note) {
        guard !reduceMotion else { NoteService.togglePin(note); return }
        pinArrivalID = note.id
        NoteService.togglePin(note)
        // Мітку знімаємо, коли проявлення вже відіграло (свій показаний
        // стан ArrivalReveal тримає сам)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if pinArrivalID == note.id { pinArrivalID = nil }
        }
    }

    private func deleteWithUndo(_ note: Note) {
        disarmHover() // кнопки не їдуть на сусідню картку (P2.12)
        settle { NoteService.softDelete(note) }
        toasts.showUndo(message: "Нотатку видалено") {
            // Undo повертає нотатку тим самим шляхом: сусіди розступаються
            disarmHover()
            settle { NoteService.undoDelete(note) }
        }
    }

    /// Вимкнути ховер на час перестановки списку (~тривалість settle
    /// із запасом); генерація захищає від раннього ре-озброєння, коли
    /// видалення йдуть підряд
    private func disarmHover() {
        hoverArmed = false
        hoverArmGeneration += 1
        let generation = hoverArmGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if hoverArmGeneration == generation { hoverArmed = true }
        }
    }

    // MARK: - Бар папок

    private func folderBar(_ slice: NoteListSlice) -> some View {
        // Лічильники всіх чіпів — ОДНИМ проходом по нотатках, а не
        // окремим O(n)-фільтром на кожну папку (перф-фікс 2026-08-16)
        let counts = (all: slice.countAll, byFolder: slice.countByFolder)
        return NotesFolderBar(
            folders: folders,
            selectedFolderID: $model.selectedFolderID,
            searchOpen: $model.searchOpen,
            searchText: $model.searchText,
            countFor: { folder in
                folder == nil ? counts.all : counts.byFolder[folder!.id] ?? 0
            },
            onSelect: { switchFolder(to: $0) },
            onCreateFolder: { name in
                guard ProGate.allowCreate() else { return } // режим читання
                if let f = NoteService.createFolder(name, existing: folders, in: context) {
                    model.selectedFolderID = f.id
                }
            },
            onDeleteFolder: { folderToDelete = $0 },
            morphNS: folderChipNS,
            addingFolder: $addingFolder
        )
    }

    private func switchFolder(to id: UUID?) {
        guard id != model.selectedFolderID else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.selectedFolderID = id
        }
    }

    // Лічильники «Всі» + по папках живуть у кеші зрізу (slice.countAll /
    // .countByFolder): окремий O(n)-прохід платив би ту саму
    // матеріалізацію, яку кеш прибрав (F5.4)

    // MARK: - Порожні стани (SPEC §8.1)

    @ViewBuilder private var emptyState: some View {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Нічого не знайдено.")
                .font(.emUI(12.5))
                .foregroundStyle(EmbarColors.ink3)
                .padding(.top, 120)
        } else if selectedFolder != nil {
            Text("У цій папці порожньо.")
                .font(.emDisplay(13, italic: true))
                .foregroundStyle(EmbarColors.ink3)
                .padding(.top, 120)
        } else {
            EmptyStateText(line1: "Нотаток ще немає.")
                .padding(.top, 120)
        }
    }
}

/// Швидкий ввід нотатки з ВЛАСНОЮ чернеткою (перф-фікс 2026-08-16, пара
/// до StickiesQuickInput): набір тексту не торкається списку — нагору йде
/// лише готовий заголовок при сабміті. Порожній Enter теж створює нотатку
/// «Без назви» (поведінка SPEC §3.1 збережена)
private struct NotesQuickInput: View {
    var autoFocus: Bool
    var onCommit: (String) -> Void

    @State private var draft = ""

    var body: some View {
        QuickComposer(placeholder: "Нова нотатка...", text: $draft,
                      autoFocus: autoFocus) {
            // Режим читання: відмова ДО очищення - текст лишається в полі
            guard ProGate.allowCreate() else { return }
            let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            onCommit(title)
            draft = ""
        }
    }
}
