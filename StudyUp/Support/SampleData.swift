import SwiftData

/// A few starter cards so a fresh install has something to try.
enum SampleData {
    private static let topics: [(topic: String, subtopics: [(name: String, cards: [(String, String)])])] = [
        ("OS Fundamentals", [
            ("Processes & Threads", [
                ("What is the difference between a process and a thread?",
                 "A process has its own address space; threads within a process share the address space but each has its own stack and registers."),
                ("What does a **context switch** save and restore?",
                 "The CPU state of the running task: registers, program counter, stack pointer (and for processes, the page table base)."),
                ("What is a race condition?",
                 "When the result depends on the timing of concurrent operations on shared state, e.g. two threads doing `count += 1` without a lock."),
            ]),
            ("Memory", [
                ("What is a page fault?",
                 "A trap raised when a program accesses a virtual page that isn't currently mapped to a physical frame, so the OS must load or allocate it."),
                ("What does the TLB cache?",
                 "Recent virtual-to-physical page translations, so most memory accesses skip the page table walk."),
            ]),
        ]),
        ("ML Foundations", [
            ("Linear Algebra", [
                ("What does an eigenvector of a matrix A satisfy?",
                 "Av = λv: A only scales v (by the eigenvalue λ) without changing its direction."),
            ]),
            ("Training", [
                ("Why scale attention scores by 1/√d?",
                 "Dot products of d-dimensional vectors grow with d; scaling keeps the softmax out of its saturated, small-gradient region."),
            ]),
        ]),
    ]

    static func insert(into context: ModelContext) {
        for (topicName, subtopics) in topics {
            let topic = Folder(name: topicName)
            context.insert(topic)
            for (subtopicName, cards) in subtopics {
                let subtopic = Folder(name: subtopicName)
                context.insert(subtopic)
                subtopic.parent = topic
                for (front, back) in cards {
                    let card = Card(front: front, back: back)
                    context.insert(card)
                    card.folder = subtopic
                }
            }
        }
    }
}
