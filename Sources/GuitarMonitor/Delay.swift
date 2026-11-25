import Foundation

/// Note lengths for the tempo-synced delay, measured in quarter-note beats.
enum DelayDivision: Int, CaseIterable, Identifiable {
    case quarter, dottedQuarter, eighth, dottedEighth, tripletEighth, sixteenth, dottedSixteenth, tripletSixteenth

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarter: "1/4"
        case .dottedQuarter: "Dotted 1/4"
        case .eighth: "1/8"
        case .dottedEighth: "Dotted 1/8"
        case .tripletEighth: "1/8 Triplet"
        case .sixteenth: "1/16"
        case .dottedSixteenth: "Dotted 1/16"
        case .tripletSixteenth: "1/16 Triplet"
        }
    }

    var beats: Double {
        switch self {
        case .quarter: 1
        case .dottedQuarter: 1.5
        case .eighth: 0.5
        case .dottedEighth: 0.75
        case .tripletEighth: 1.0 / 3
        case .sixteenth: 0.25
        case .dottedSixteenth: 0.375
        case .tripletSixteenth: 1.0 / 6
        }
    }

    /// Delay time in seconds at the given tempo.
    func seconds(bpm: Double) -> Double { 60 / max(bpm, 1) * beats }
}

enum DelayLimits {
    static let bpmRange: ClosedRange<Double> = 40...240
    /// Apple's delay unit tops out at 2 seconds.
    static let maxSeconds = 2.0
}
