import Foundation

/// One user save keeps one server idempotency key, including ambiguous network
/// failures. A confirmed intent is finalized on retry without another confirmation.
struct CardSaveAttempt {
    private(set) var requestID = UUID().uuidString
    private(set) var isBusy = false
    private(set) var confirmedIntentID: String?
    private(set) var completed = false
    mutating func begin() -> String? {
        guard !isBusy, !completed else { return nil }
        isBusy = true
        return requestID
    }
    mutating func confirmed(_ id: String) { confirmedIntentID = id }
    mutating func failed() { isBusy = false }
    mutating func succeeded() { completed = true; isBusy = false }
    mutating func edited() {
        guard !isBusy, !completed, confirmedIntentID == nil else { return }
        requestID = UUID().uuidString
    }
}
