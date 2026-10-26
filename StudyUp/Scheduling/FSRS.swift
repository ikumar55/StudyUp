import Foundation

/// The grade given after answering a card. Raw values match FSRS grades (1 = Again ... 4 = Easy);
/// StudyUp doesn't use "Hard", so grade 2 is absent.
nonisolated enum Rating: Int, CaseIterable, Sendable {
    case again = 1
    case good = 3
    case easy = 4
}

nonisolated enum CardState: Int, Sendable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

/// Everything the scheduler needs to know about a card, independent of storage.
nonisolated struct CardSchedule: Equatable, Sendable {
    var state: CardState = .new
    var due: Date
    var stability: Double = 0
    var difficulty: Double = 0
    var step: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?
    /// Picks this card's interval fuzz (see `FSRS.fuzzed`). Nil means no fuzz.
    var fuzzSeed: UInt64?

    /// A card's fuzz seed, from its sync id: stable for the card's lifetime, different between cards.
    static func fuzzSeed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) }
    }
}

/// FSRS-5 (Free Spaced Repetition Scheduler), the algorithm Anki uses by default.
/// Cards in learning/relearning go through short fixed steps before graduating to day-scale intervals.
/// Reference: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
nonisolated struct FSRS: Sendable {
    static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]

    /// Steps for cards still being learned, sized for studying through the day in reminders rather
    /// than in long sessions: Wrong waits 15 minutes, so the card comes back in the *next* reminder;
    /// Right waits 3 hours, a same-day check that it stuck; Right again graduates to days.
    static let defaultLearningSteps: [TimeInterval] = [15 * 60, 3 * 3600]
    /// A forgotten card comes back in the next reminder; Right then returns it to day-scale reviews.
    static let defaultRelearningSteps: [TimeInterval] = [15 * 60]

    private static let decay = -0.5
    private static let factor = 19.0 / 81.0
    private static let secondsPerDay: TimeInterval = 86_400

    var weights: [Double]
    var desiredRetention: Double
    var learningSteps: [TimeInterval]
    var relearningSteps: [TimeInterval]
    var maximumIntervalDays: Int

    init(
        weights: [Double] = FSRS.defaultWeights,
        desiredRetention: Double = 0.9,
        learningSteps: [TimeInterval] = FSRS.defaultLearningSteps,
        relearningSteps: [TimeInterval] = FSRS.defaultRelearningSteps,
        maximumIntervalDays: Int = 36_500
    ) {
        precondition(weights.count == 19, "FSRS-5 needs 19 weights")
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumIntervalDays = maximumIntervalDays
    }

    /// The card's next schedule for every rating, so buttons can show the resulting interval.
    func preview(_ card: CardSchedule, now: Date) -> [Rating: CardSchedule] {
        var results = Dictionary(uniqueKeysWithValues: Rating.allCases.map { ($0, schedule(card, rating: $0, now: now)) })
        // Easy must always wait longer than Good.
        if let good = results[.good], var easy = results[.easy],
           good.state == .review, easy.state == .review, easy.due <= good.due {
            easy.due = good.due.addingTimeInterval(Self.secondsPerDay)
            results[.easy] = easy
        }
        return results
    }

    func review(_ card: CardSchedule, rating: Rating, now: Date) -> CardSchedule {
        preview(card, now: now)[rating]!
    }

    /// Probability of recalling a card `elapsedDays` after its last review.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + Self.factor * elapsedDays / stability, Self.decay)
    }

    /// Days until retrievability falls to `desiredRetention`.
    func intervalDays(stability: Double) -> Int {
        let raw = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(max(Int(raw.rounded()), 1), maximumIntervalDays)
    }

    // MARK: - Fuzz

    /// How far an interval may move, as Anki and the FSRS reference schedulers do it: a day, plus 15% of
    /// the part between 2.5 and 7 days, 10% of the part between 7 and 20, and 5% beyond.
    private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7, 0.15), (7, 20, 0.1), (20, .infinity, 0.05),
    ]

    /// Nudges an interval of 3 days or more a little earlier or later (4 days → 3–5, 14 → 12–16,
    /// 44 → 40–48), so cards learned together don't keep coming due on the same days. The nudge comes
    /// from the card's seed and review count, not the time, so the label on a button (shown before
    /// grading) always matches what grading does.
    static func fuzzed(_ days: Int, seed: UInt64?, reps: Int, maximum: Int) -> Int {
        guard let seed, Double(days) >= 2.5 else { return days }
        let interval = Double(days)
        let delta = fuzzRanges.reduce(1.0) { $0 + $1.factor * max(min(interval, $1.end) - $1.start, 0) }
        let high = min(Int((interval + delta).rounded()), maximum)
        let low = min(max(2, Int((interval - delta).rounded())), high)
        let fraction = Double(splitMix(seed &+ UInt64(reps) &* 0x9E37_79B9_7F4A_7C15) >> 11) / Double(1 << 53)
        return min(low + Int(fraction * Double(high - low + 1)), high)
    }

    /// A well-mixed 64-bit hash (SplitMix64), so nearby seeds and review counts give unrelated nudges.
    private static func splitMix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // MARK: - Scheduling

    private func schedule(_ card: CardSchedule, rating: Rating, now: Date) -> CardSchedule {
        var next = card
        next.reps += 1
        next.lastReview = now
        updateMemoryState(&next, from: card, rating: rating, now: now)

        func graduate() {
            next.state = .review
            next.step = 0
            let days = Self.fuzzed(
                intervalDays(stability: next.stability), seed: card.fuzzSeed, reps: card.reps, maximum: maximumIntervalDays
            )
            next.due = now.addingTimeInterval(TimeInterval(days) * Self.secondsPerDay)
        }

        func enterStep(_ step: Int, of steps: [TimeInterval], as state: CardState) {
            next.state = state
            next.step = step
            next.due = now.addingTimeInterval(steps[step])
        }

        switch card.state {
        case .new, .learning, .relearning:
            let steps = card.state == .relearning ? relearningSteps : learningSteps
            let stepState: CardState = card.state == .relearning ? .relearning : .learning
            switch rating {
            case .again where !steps.isEmpty:
                enterStep(0, of: steps, as: stepState)
            case .good where card.step + 1 < steps.count:
                enterStep(card.step + 1, of: steps, as: stepState)
            default:
                graduate()
            }
        case .review:
            if rating == .again {
                next.lapses += 1
                if relearningSteps.isEmpty { graduate() } else { enterStep(0, of: relearningSteps, as: .relearning) }
            } else {
                graduate()
            }
        }
        return next
    }

    private func updateMemoryState(_ next: inout CardSchedule, from card: CardSchedule, rating: Rating, now: Date) {
        let grade = Double(rating.rawValue)
        guard card.state != .new else {
            next.stability = initialStability(rating)
            next.difficulty = initialDifficulty(grade)
            return
        }
        let elapsedDays = card.lastReview.map { max(0, now.timeIntervalSince($0) / Self.secondsPerDay) } ?? 0
        if elapsedDays < 1 {
            next.stability = shortTermStability(card.stability, grade: grade)
        } else {
            let r = retrievability(elapsedDays: elapsedDays, stability: card.stability)
            next.stability = rating == .again
                ? forgetStability(difficulty: card.difficulty, stability: card.stability, retrievability: r)
                : recallStability(difficulty: card.difficulty, stability: card.stability, retrievability: r, rating: rating)
        }
        next.difficulty = nextDifficulty(card.difficulty, grade: grade)
    }

    // MARK: - FSRS-5 formulas

    private var w: [Double] { weights }

    private func initialStability(_ rating: Rating) -> Double {
        max(w[rating.rawValue - 1], 0.1)
    }

    private func initialDifficulty(_ grade: Double) -> Double {
        clampDifficulty(w[4] - exp(w[5] * (grade - 1)) + 1)
    }

    private func nextDifficulty(_ d: Double, grade: Double) -> Double {
        let delta = -w[6] * (grade - 3)
        let damped = d + delta * (10 - d) / 9
        let reverted = w[7] * initialDifficulty(4) + (1 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    private func recallStability(difficulty d: Double, stability s: Double, retrievability r: Double, rating: Rating) -> Double {
        let easyBonus = rating == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * easyBonus)
    }

    private func forgetStability(difficulty d: Double, stability s: Double, retrievability r: Double) -> Double {
        let forgotten = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
        return max(min(forgotten, s / exp(w[17] * w[18])), 0.1)
    }

    /// Stability change for a review on the same day as the previous one (learning steps).
    private func shortTermStability(_ s: Double, grade: Double) -> Double {
        var multiplier = exp(w[17] * (grade - 3 + w[18]))
        if grade >= 3 { multiplier = max(multiplier, 1) }
        return max(s * multiplier, 0.1)
    }

    private func clampDifficulty(_ d: Double) -> Double {
        min(max(d, 1), 10)
    }
}
