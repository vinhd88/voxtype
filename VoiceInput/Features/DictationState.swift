import Foundation

/// Single source of truth for dictation workflow state.
enum DictationState: Equatable {
    case idle
    case listening
    case transcribing
    case done(text: String)
    case error(message: String)

    var isProcessing: Bool {
        self == .listening || self == .transcribing
    }
}
