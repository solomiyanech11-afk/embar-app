//
//  StickyColorMode.swift
//  Embar
//
//  Ефективний колір стіка (SPEC §2.1, фідбек 2026-07-03). У режимі byWall
//  колір ВИВОДИТЬСЯ зі стіни (або кольору «без стіни»), тож переміщення
//  стіка між стінами одразу міняє його колір, а зміна кольору стіни —
//  колір усіх її стіків. У режимі random — власний colorIndex стіка.
//

import Foundation

enum StickyColorMode {
    /// Індекс кольору в палітру для показу картки
    static func effectiveIndex(for sticker: Sticker, byWall: Bool, noWallSlot: Int) -> Int {
        guard byWall else { return sticker.colorIndex }
        if let wall = sticker.wall, wall.deletedAt == nil {
            return wall.effectiveColorSlot
        }
        return noWallSlot
    }
}
