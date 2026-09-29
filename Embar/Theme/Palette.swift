//
//  Palette.swift
//  Embar
//
//  15 палітр — точні hex і порядок меню з Embar.md §9.2 (звірено з прототипом 1:1).
//  Кожна палітра = 5 кольорів стіків (--sticky-1..5) + акцент (--accent).
//  Палітра впливає на: стіки, акценти, кільце «сьогодні», прогрес, події таймлайну,
//  пін-декоратор. НЕ впливає на хайлайти рідера (вони фіксовані — див. EmbarColors).
//

import SwiftUI

struct Palette: Identifiable, Equatable {
    /// Стабільний ідентифікатор (зберігається в налаштуваннях)
    let slug: String
    /// Назва в меню
    let name: String
    /// 5 кольорів стіків
    let sticky: [Color]
    let accent: Color

    var id: String { slug }

    static let all: [Palette] = [
        // ❗ Акцент Cream — БРЕНДОВИЙ (фідбек 2026-08-17). Був вохристий
        // #c97a3a із §9.2/прототипу: єдиний яскраво-теплий серед 15
        // акцентів (решта — глибокі приглушені), і в кільцях прогресу та
        // «🔥 N» читався випадковою помаранчевою плямою. Дефолтна палітра
        // тепер носить колір бренду; решта 14 лишились як були
        Palette(slug: "cream", name: "Cream",
                hexes: ["#fef9c3", "#dbeafe", "#dcfce7", "#fce7f3", "#ede9fe"],
                accent: EmbarColors.brandRed),
        Palette(slug: "lavender", name: "Lavender Fields",
                hexes: ["#E6DDF0", "#E2D3F2", "#D0BFDD", "#C9BEDA", "#B1A4C3"], accentHex: "#5B506C"),
        Palette(slug: "matcha", name: "Matcha",
                hexes: ["#EFF2D6", "#DDE3BA", "#B6C77B", "#92AA58", "#7C9047"], accentHex: "#455826"),
        Palette(slug: "raspberry", name: "Raspberry",
                hexes: ["#FAECEE", "#F5D5D9", "#EAA6AE", "#D8798A", "#C46370"], accentHex: "#823C44"),
        Palette(slug: "sky", name: "Sky",
                hexes: ["#EDF0EE", "#DAE0DD", "#C6D4DD", "#BBD0DC", "#AFC0D4"], accentHex: "#AFC0D4"),
        Palette(slug: "matchaberry", name: "Matchaberry",
                hexes: ["#FCEBF1", "#F4C7D0", "#D7DAB3", "#C66F80", "#9FAA74"], accentHex: "#4A6644"),
        Palette(slug: "picnic", name: "Picnic",
                hexes: ["#EFE2CA", "#F6D387", "#CFBBA2", "#AF9273", "#D4A85A"], accentHex: "#8A6946"),
        Palette(slug: "wedding", name: "Wedding",
                hexes: ["#FFF0D6", "#FECDBE", "#B7C8D8", "#C7C294", "#F59B90"], accentHex: "#A9AA74"),
        Palette(slug: "sunset", name: "Sunset Field",
                hexes: ["#ECDCD1", "#E8D0DC", "#CEB6C0", "#BFB7D4", "#BB998B"], accentHex: "#5B6A57"),
        Palette(slug: "coastal", name: "Coastal Girl",
                hexes: ["#F7EFE2", "#E5EDF0", "#DDCDBD", "#CCA586", "#9FADB6"], accentHex: "#A49284"),
        Palette(slug: "vanilla", name: "Vanilla Cloud",
                hexes: ["#F2EEEC", "#EBE3E0", "#E6D7C8", "#CEC6C2", "#D5B2A7"], accentHex: "#A38F85"),
        Palette(slug: "terracotta", name: "Strawberry Kiss",
                hexes: ["#E2B8AD", "#D2BDAB", "#C6B8AB", "#CFA195", "#A59383"], accentHex: "#6D322A"),
        Palette(slug: "petal", name: "Petal Ritual",
                hexes: ["#F5EEE8", "#F2D4D6", "#F4CB82", "#D8D1BE", "#C9D8E5"], accentHex: "#B08B8C"),
        Palette(slug: "studio", name: "Studio",
                hexes: ["#e9f056", "#ff8d6b", "#d7efff", "#aeb8a0", "#c8b8e0"], accentHex: "#2563eb"),
        Palette(slug: "ponyo", name: "Ponyo",
                hexes: ["#ECCCA6", "#99BFD5", "#F7A088", "#E95C6C", "#47748B"], accentHex: "#27456C"),
    ]

    /// Палітра за замовчуванням для нових користувачів — Cream.
    /// Один константний слаг замість чотирьох літералів "cream" по
    /// файлах: інакше «дефолт» тримався на тому, що всі чотири збіглись
    static let defaultSlug = "cream"

    static func bySlug(_ slug: String) -> Palette {
        all.first { $0.slug == slug } ?? byDefault
    }

    /// Cream — перша в списку; шукаємо за слагом, а не за індексом, щоб
    /// перестановка меню не змінила дефолт мовчки
    static var byDefault: Palette {
        all.first { $0.slug == defaultSlug } ?? all[0]
    }

    private init(slug: String, name: String, hexes: [String], accentHex: String) {
        self.slug = slug
        self.name = name
        self.sticky = hexes.map { Color(hex: $0) }
        self.accent = Color(hex: accentHex)
    }

    /// Той самий init, але акцент — готовий токен, а не hex (Cream носить
    /// брендовий; дублювати його значення рядком означало б два джерела)
    private init(slug: String, name: String, hexes: [String], accent: Color) {
        self.slug = slug
        self.name = name
        self.sticky = hexes.map { Color(hex: $0) }
        self.accent = accent
    }
}

/// Відтінок фону панелі — вибір у Settings «фон панелі» (2026-07-19).
/// Спокійні, близькі до білого: контраст чорнила і білих карток зберігається
enum PanelSurface: String, CaseIterable {
    case warm, white, shell, mist, sage

    /// Не View, тому переклад тягнемо явно через String(localized:)
    var name: String {
        switch self {
        // .warm — сьогоднішній #fcfbf9, дефолт
        case .warm: String(localized: "Теплий", comment: "Назва фону панелі")
        case .white: String(localized: "Білий", comment: "Назва фону панелі")
        case .shell: String(localized: "Мушля", comment: "Назва фону панелі")
        case .mist: String(localized: "Туман", comment: "Назва фону панелі")
        case .sage: String(localized: "Шавлія", comment: "Назва фону панелі")
        }
    }

    var color: Color {
        switch self {
        case .warm: Color(hex: "#fcfbf9")
        case .white: Color(hex: "#ffffff")
        case .shell: Color(hex: "#fdf6ee")
        case .mist: Color(hex: "#f4f6f7")
        case .sage: Color(hex: "#f4f6f1")
        }
    }

    static var current: PanelSurface {
        PanelSurface(rawValue: EmbarDefaults.store
            .string(forKey: "panelSurface") ?? "") ?? .warm
    }
}

/// Базові токени, що НЕ залежать від палітри (Embar.md §9.3, прототип :root)
enum EmbarColors {
    /// Сцена за панеллю
    static let bg = Color(hex: "#e8e4df")
    /// Поверхня панелі — динамічний токен: читає вибір «фон панелі»
    /// з Settings (перерендер їде через ThemeStore.objectWillChange)
    static var surface: Color { PanelSurface.current.color }
    /// Картки контенту
    static let card = Color.white
    /// Основний текст
    static let ink = Color(hex: "#1a1a1a")
    /// Вторинний текст
    static let ink2 = Color(hex: "#555555")
    /// Приглушений / мета
    static let ink3 = Color(hex: "#999999")
    /// Disabled
    static let ink4 = Color(hex: "#cccccc")
    /// Плейсхолдери полів вводу — ЄДИНИЙ токен для всіх поверхонь
    /// (рішення 2026-07-22: 14pt скрізь, тон — середина між колишнім
    /// стіковим #6f6f68 і рідерівським #ddd8d2)
    static let placeholder = Color(hex: "#a6a39d")
    /// Лінії / розділювачі
    static let line = Color.black.opacity(0.07)
    /// Тінти (hover-фони)
    static let tint = Color.black.opacity(0.05)
    static let tint2 = Color.black.opacity(0.08)

    /// Хайлайти рідера — фіксовані, не залежать від палітри (SPEC §13)
    static let highlightYellow = Color(hex: "#fbe6a0")
    static let highlightPurple = Color(hex: "#d9c9f0")
    static let highlightBlue = Color(hex: "#c5dbf4")
    static let highlightRed = Color(hex: "#f4c8c8")

    // MARK: - Червоні: дві РОЛІ, два токени (ревізія 2026-08-17)
    //
    // До ревізії в продукті жило шість різних червоних, і бренд плутався
    // з «небезпекою». Тепер рівно два, і кожен має одну роль.

    /// БРЕНД — ідентичність: знак у хедері, кнопки знайомства, ореол
    /// шестерні, іконка застосунку. Ніколи не означає «небезпека».
    ///
    /// ❗ Значення взято з ОРИГІНАЛУ лого — `logo-master/logoColor.png`,
    /// РАВ-піксель #FE3B43 (профіль файлу sRGB). Хедер до ревізії малював
    /// #FF5453, знайомство — #F93B3B: обидва були примірками «на око» і
    /// розійшлися з асетом. Якщо колись знадобиться звірити — читати
    /// саме РАВ-пікселі: колірно-керована конвертація NSImage дає інше
    /// число (#FF5554), і саме так у код колись потрапила неправда.
    static let brandRed = Color(hex: "#FE3B43")
    /// Світлий кінець брендових градієнтів (блиск кнопки знайомства).
    /// Це не окрема ідентичність — лише highlight того самого червоного
    static let brandRedLight = Color(hex: "#FF6A62")
    /// Мʼятний бренду — тло знака в оригіналі лого (той самий РАВ-замір)
    static let brandMint = Color(hex: "#E2F2F3")

    /// ФУНКЦІЯ — єдиний danger: видалити · дедлайн · помилка вводу.
    /// Замінив #c45e5e / #e74c3c / #b91c1c (рішення 2026-08-17: contrast
    /// 5.4:1 білим текстом на заливці — AA; #c45e5e давав 4.1:1 і не
    /// проходив, а #e74c3c був майже близнюком brandRed)
    static let danger = Color(hex: "#c0392b")
}
