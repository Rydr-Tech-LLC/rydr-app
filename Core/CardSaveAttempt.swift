import Foundation

/// One user save keeps one server idempotency key, including ambiguous network
/// failures. A confirmed intent is finalized on retry without another confirmation.
struct CardSaveAttempt {
    private(set) var requestID = UUID().uuidString
    private(set) var isBusy = false
    private(set) var confirmedIntentID: String?
    private(set) var completed = false
    private var attemptCreatedAt = Date()
    private var persistenceKey: String?
    private(set) var restored = false

    // Persist only opaque attempt/intent IDs, never card details or client secrets.
    // Account + workspace isolation prevents a resumed save crossing identities.
    mutating func bind(scope: String) {
        let key = "rydr.cardSave." + scope
        guard persistenceKey != key else { return }
        persistenceKey = key
        requestID = UUID().uuidString
        attemptCreatedAt = Date()
        confirmedIntentID = nil
        restored = false
        completed = false
        if let saved = UserDefaults.standard.dictionary(forKey: key),
           let id = saved["requestID"] as? String,
           let date = saved["date"] as? Date,
           Date().timeIntervalSince(date) < 12 * 60 * 60 {
            restored = true
            attemptCreatedAt = date
            requestID = id
            confirmedIntentID = saved["intentID"] as? String
        }
    }
    private func persist() {
        guard let persistenceKey else { return }
        var saved: [String: Any] = ["requestID": requestID, "date": attemptCreatedAt]
        if let confirmedIntentID { saved["intentID"] = confirmedIntentID }
        UserDefaults.standard.set(saved, forKey: persistenceKey)
    }
    mutating func begin() -> String? {
        guard !isBusy, !completed else { return nil }
        isBusy = true
        persist()
        return requestID
    }
    mutating func confirmed(_ id: String) { confirmedIntentID = id; persist() }
    mutating func failed() { isBusy = false }
    mutating func succeeded() { completed = true; isBusy = false; if let persistenceKey { UserDefaults.standard.removeObject(forKey: persistenceKey) } }
    mutating func edited() {
        guard !isBusy, !completed, confirmedIntentID == nil else { return }
        requestID = UUID().uuidString
    }
}


/// Bounded recovery only for idempotent card-setup operations. A timeout must
/// reuse the exact request body/key because the server may have completed it.
enum CardSaveTransport {
    static func isTransient(_ error: Error?, status: Int?) -> Bool {
        if let error {
            guard let error = error as? URLError else { return false }
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
        }
        return status.map { $0 == 429 || (500...599).contains($0) } ?? false
    }
    static func perform(_ request: URLRequest, retryable: Bool, attemptsLeft: Int = 2, session: URLSession = .shared,
                        completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        var request = request
        request.timeoutInterval = 20
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            if retryable && attemptsLeft > 0 && isTransient(error, status: status) {
                let retryRequest = request
                DispatchQueue.global().asyncAfter(deadline: .now() + (attemptsLeft == 2 ? 0.5 : 1.5)) {
                    perform(retryRequest, retryable: true, attemptsLeft: attemptsLeft - 1, session: session, completion: completion)
                }
            } else { completion(data, response, error) }
        }.resume()
    }
}
