import Combine
import Foundation

/// Bridge Pro: photos, Bridge Cloud's natural voice and the Ask/Look Shortcuts actions. Voice conversations stay free.
/// The personal (sideloaded) build has everything unlocked; only the App Store build sells Pro.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// The self-hosted app's privacy notes and licence, in the public relay repo.
    static let privacyURL = URL(string: "https://github.com/stephen3303/bridge-relay#privacy")!
    static let termsURL = URL(string: "https://github.com/stephen3303/bridge-relay/blob/main/LICENSE")!

    @Published private(set) var isPro = true

    private init() {
    }

    func refresh() async {
    }


    /// Bridge Cloud checks Apple's signature on the transaction itself before it unlocks the natural voice and photos.
    /// Until it has answered for this one (offline, a timeout), cloud voice and photo calls try again, briefly so
    /// a spoken reply isn't held up. A refusal (another account's subscription) is an answer: retrying won't change it.
    func reportIfNeeded() async {
    }

    /// The one description of what Pro gives, used in the settings section and the subscription sheet.
    static let summary = "Photos from your glasses, the natural voice on Bridge Cloud (turn on Natural voice in Settings), and the Ask and Look actions for Shortcuts. Voice conversations stay free."

    enum Locked: LocalizedError {
        case needsPro
        var errorDescription: String? { "That needs Bridge Pro. Open Bridge to start a free trial." }
    }

    func requirePro() throws {
        guard isPro else { throw Locked.needsPro }
    }
}
