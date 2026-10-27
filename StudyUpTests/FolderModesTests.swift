import Foundation
import SwiftData
import Testing
@testable import StudyUp

@MainActor
struct FolderModesTests {
    let container: ModelContainer
    let context: ModelContext
    let modes = FolderModes(defaults: nil)

    // OS › Memory, OS › Processes, and ML, with one card in each.
    let os: Folder, memory: Folder, processes: Folder, ml: Folder
    let pageFault: Card, contextSwitch: Card, gradient: Card

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        (os, memory, processes, ml) = (Folder(name: "OS"), Folder(name: "Memory"), Folder(name: "Processes"), Folder(name: "ML"))
        for folder in [os, memory, processes, ml] { context.insert(folder) }
        memory.parent = os
        processes.parent = os
        (pageFault, contextSwitch, gradient) = (Card(front: "page fault", back: ""), Card(front: "context switch", back: ""), Card(front: "gradient", back: ""))
        for (card, folder) in [(pageFault, memory), (contextSwitch, processes), (gradient, ml)] {
            context.insert(card)
            card.folder = folder
        }
    }

    private var comingUp: [String] {
        [pageFault, contextSwitch, gradient].filter(modes.includes).map(\.front)
    }

    @Test func everythingComesUpByDefault() {
        #expect(comingUp == ["page fault", "context switch", "gradient"])
        #expect([os, memory, ml].allSatisfy(modes.isActive))
    }

    @Test func pausingATopicPausesEverythingInside() {
        modes.set(.paused, for: os)
        #expect(comingUp == ["gradient"])
        #expect(!modes.isActive(os) && !modes.isActive(memory))
        #expect(modes.mode(of: os) == .paused && modes.mode(of: memory) == .normal)
    }

    @Test func pausingSeveralFolders() {
        modes.set(.paused, for: memory)
        modes.set(.paused, for: ml)
        #expect(comingUp == ["context switch"])
    }

    @Test func focusingASubfolderLeavesOnlyItsCards() {
        modes.set(.focused, for: memory)
        #expect(comingUp == ["page fault"])
        #expect(modes.isActive(os), "it holds the focused folder")
        #expect(!modes.isActive(processes) && !modes.isActive(ml))
    }

    @Test func focusingSeveralFolders() {
        modes.set(.focused, for: memory)
        modes.set(.focused, for: ml)
        #expect(comingUp == ["page fault", "gradient"])
    }

    @Test func pauseWinsInsideAFocusedFolder() {
        modes.set(.focused, for: os)
        modes.set(.paused, for: memory)
        #expect(comingUp == ["context switch"])
    }

    @Test func resumingAndStoppingBringCardsBack() {
        modes.set(.paused, for: os)
        modes.set(.focused, for: ml)
        modes.set(.normal, for: os)
        modes.set(.normal, for: ml)
        #expect(comingUp.count == 3)
    }

    @Test func aDeletedFocusedFolderNoLongerHidesEverything() {
        modes.set(.focused, for: ml)
        modes.forget(ml.allFolders.compactMap(\.syncID))
        #expect(comingUp.count == 3)
    }

    @Test func modesAreRememberedAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "FolderModesTests"))
        defer { defaults.removePersistentDomain(forName: "FolderModesTests") }
        FolderModes(defaults: defaults).set(.paused, for: ml)
        #expect(FolderModes(defaults: defaults).mode(of: ml) == .paused)
    }
}
