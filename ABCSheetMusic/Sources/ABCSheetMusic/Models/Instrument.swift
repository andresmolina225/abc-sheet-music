import Foundation

/// Jazz transposition: written pitch interval above concert.
enum Instrument: String, CaseIterable, Identifiable, Codable {
    case tenor
    case alto
    case bb
    case concert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tenor:   return "Tenor Sax (Bb)"
        case .alto:    return "Alto Sax (Eb)"
        case .bb:      return "Bb Clarinet / Trumpet"
        case .concert: return "Concert Pitch"
        }
    }

    var shortName: String {
        switch self {
        case .tenor:   return "Tenor Sax"
        case .alto:    return "Alto Sax"
        case .bb:      return "Bb"
        case .concert: return "Concert"
        }
    }

    var intervalLabel: String? {
        switch self {
        case .tenor:   return "maj 9th"
        case .alto:    return "maj 6th"
        case .bb:      return "maj 2nd"
        case .concert: return nil
        }
    }

    /// Semitones to transpose written pitch above concert.
    var transposeSteps: Int {
        switch self {
        case .tenor:   return 14
        case .alto:    return 9
        case .bb:      return 2
        case .concert: return 0
        }
    }

    /// Playback offset so audio stays at concert pitch.
    var midiTranspose: Int { -transposeSteps }

    var midiProgram: Int {
        switch self {
        case .tenor:   return 66
        case .alto:    return 65
        case .bb:      return 61
        case .concert: return 0
        }
    }

    /// Comfortable written MIDI range for octave fitting.
    var writtenRange: ClosedRange<Int>? {
        switch self {
        case .tenor:   return 58...86
        case .alto:    return 55...84
        case .bb:      return 60...84
        case .concert: return nil
        }
    }

    var menuTitle: String {
        switch self {
        case .tenor:   return "Tenor Sax — maj 9th (+14)"
        case .alto:    return "Alto Sax — maj 6th (+9)"
        case .bb:      return "Bb Clarinet / Trumpet — maj 2nd (+2)"
        case .concert: return "Concert Pitch"
        }
    }

    var statusText: String {
        guard transposeSteps > 0, let interval = intervalLabel else {
            return "Concert · 0 st"
        }
        return "\(shortName) · \(interval) (+\(transposeSteps) st)"
    }
}