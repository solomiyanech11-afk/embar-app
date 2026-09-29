//
//  StickiesModel.swift
//  Embar
//
//  Спільний стан поверхні «Стіки», піднятий на рівень панелі, щоб лист
//  налаштувань (і його скрим) накривав УСЮ панель — хедер, таби, футер —
//  а не лише область стіни (фідбек 2026-07-03).
//
//  Тут же живе КЕШ ЗРІЗУ СТІНИ (F5, 2026-08-28): секції + лічильники
//  перераховуються не на кожен body, а лише коли змінюється вибірка
//  (стіна/фільтр/емоджі) або приходить масова мутація; зміна одного
//  стіка правиться точковим патчем. Механізм — StickyWallSlice.swift.
//

import SwiftUI
import Combine

@MainActor
final class StickiesModel: ObservableObject {
    @Published var selectedWallID: UUID?
    @Published var filterKind: StickyFilterKind = .all
    /// Фільтр за емоджі-тегом (чіпи-емоджі в «Показувати»); ортогонально
    /// НЕ живе — вибір емоджі скидає kind на .all і навпаки
    @Published var emojiFilter: String?
    @Published var showingSettings = false
    /// Стіна, для якої відкрито віконце-питання видалення
    /// (лише стіну чи разом зі стіками — фідбек 2026-07-07)
    @Published var wallPendingDelete: Wall?
    /// Нотатка → стік-джерело (SPEC §12.1 зворотний бік): доскролити до
    /// стіка і підсвітити відскоком (паттерн reader.pendingFlashEntryID)
    @Published var pendingFlashStickerID: UUID?

    // MARK: - Кеш зрізу стіни (F5)

    private let sliceEngine = WallSliceEngine()
    /// true → наступний slice() робить повний перерахунок. НЕ @Published:
    /// перемальовку і так тягне мутація (@Query), другий тригер дав би
    /// подвійний рендер
    private var sliceDirty = true
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            // Точкова мутація одного стіка — патч кеша ДО того, як SwiftUI
            // перерендерить body (пост синхронний, тим самим тактом)
            center.addObserver(forName: .embarStickerMutated, object: nil,
                               queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let sticker = note.object as? Sticker,
                          !self.sliceDirty else { return }
                    self.sliceEngine.update(sticker)
                }
            },
            // Масова зміна (maintenance/міграції/сідери) — чесний перерахунок
            center.addObserver(forName: .embarStickersBulkChanged, object: nil,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sliceDirty = true }
            },
            // Зміна дня: фільтр «Сьогодні» залежить від дати обчислення —
            // вчорашній кеш йому бреше
            center.addObserver(forName: .embarDayChanged, object: nil,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sliceDirty = true }
            },
        ]
    }

    nonisolated deinit { // захист від міни ізольованого deinit — див. CLAUDE.md
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Зріз стіни для body. `wall` — ЖИВА вибрана стіна (вже відфільтрована
    /// від soft-deleted у вьюсі). ❗ `all` — @autoclosure і читається ЛИШЕ
    /// при повному перерахунку: сам доступ до масиву @Query після мутації
    /// матеріалізує всі обʼєкти наново (~300 мс на 5000 — виміряно зондом
    /// 2026-08-28, це і був залишок після кешування секцій). Кеш-хіт не
    /// сміє його торкатись
    func slice(all: @autoclosure () -> [Sticker], wall: Wall?) -> WallSlice {
        let fp = WallSliceEngine.Fingerprint(wallID: wall?.id, kind: filterKind,
                                             emoji: emojiFilter)
        #if DEBUG
        let probeStart = PerfProbe.isActive ? CFAbsoluteTimeGetCurrent() : 0
        #endif
        if sliceDirty || sliceEngine.fingerprint != fp {
            let materialized = all()
            sliceEngine.rebuild(all: materialized, fingerprint: fp)
            sliceDirty = false
            sliceDivergedOnce = false // свіжа збірка — старі гонки забуто
            #if DEBUG
            if PerfProbe.isActive {
                PerfProbe.shared.record("stickies.sections(\(materialized.count) всього)",
                                        seconds: CFAbsoluteTimeGetCurrent() - probeStart)
            }
            #endif
        } else {
            #if DEBUG
            // Кеш-хіт: своя мітка, інакше зонд показував би нулі й ховав
            // би регресії
            if PerfProbe.isActive {
                PerfProbe.shared.record("stickies.sections.cached",
                                        seconds: CFAbsoluteTimeGetCurrent() - probeStart)
            }
            // Умова ЗЗОВНІ виклику: інакше all() матеріалізувався б і в
            // релізі, повертаючи ту саму ціну, яку кеш прибрав
            if SandboxEnvironment.isActive, !PerfProbe.isActive {
                verifySliceInSandbox(all: all(), fingerprint: fp)
            }
            #endif
        }
        return sliceEngine.slice
    }

    /// ЗАПОБІЖНИК РОЗХОДЖЕННЯ (план F5, вимога 2): у пісочниці кожен
    /// кеш-хіт звіряється з повним перерахунком. Розбіжність означає, що
    /// якийсь шлях мутації не постить StickerMutation — падаємо голосно
    /// з точним описом, бо тихий стейл-кеш означав би «стіна бреше»
    /// (прецедент: fatalError суїта пісочниці в SandboxEnvironment).
    /// Під -SandboxPerfProbe вимкнено: звірка сама O(n) і зіпсувала б
    /// заміри — еквівалентність там тримають StickyWallSliceTests.
    /// У релізі гілка мертва (SandboxEnvironment.isActive == false)
    /// Розходження з попереднього рендера — падаємо лише при повторі
    /// (2026-09-01, та сама гонка, що в NotesModel: кеш патчиться
    /// синхронно, @Query наздоганяє на такт пізніше; одноразове
    /// розходження — гонка кадру, стабільне — справжній стейл)
    private var sliceDivergedOnce = false

    private func verifySliceInSandbox(all: [Sticker],
                                      fingerprint fp: WallSliceEngine.Fingerprint) {
        let reference = WallSliceEngine.computeReference(all: all, fingerprint: fp)
        guard let divergence = sliceEngine.divergence(from: reference) else {
            sliceDivergedOnce = false
            return
        }
        guard sliceDivergedOnce else {
            sliceDivergedOnce = true
            return
        }
        fatalError("""
            Кеш зрізу стіни розійшовся з перерахунком ДВІЧІ ПОСПІЛЬ: \
            \(divergence). \
            Fingerprint: стіна \(fp.wallID?.uuidString ?? "всі"), \
            фільтр \(fp.kind.rawValue), емоджі \(fp.emoji ?? "-"). \
            Найімовірніше, якийсь шлях мутації стіків не викликає \
            StickerMutation.changed/bulkChanged — звір список у плані F5.
            """)
    }
}
