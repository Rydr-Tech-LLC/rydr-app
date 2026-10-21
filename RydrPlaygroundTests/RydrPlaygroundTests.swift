import Foundation
import Testing
@testable import RydrPlayground

struct RydrPlaygroundTests {
    @Test func submittedIdentityCanContinueWithoutAwardingVerification() {
        for value in ["processing", "verified"] {
            let status = RiderIdentityStatus(identityVerified: false, verifiedRider: false, verifiedBadge: false, identityStatus: value)
            #expect(status.allowsOnboardingContinuation)
            #expect(!status.verifiedBadge)
        }
        for value in ["not_started", "requires_input", "canceled", "failed"] {
            #expect(!RiderIdentityStatus(identityVerified: false, verifiedRider: false, verifiedBadge: false, identityStatus: value).allowsOnboardingContinuation)
        }
    }

    @Test func relativeBackendURLsRemainAbsoluteAndWorkspaceScoped() throws {
        let workspace = RydrWorkspace.identifier ?? "unresolved"
        for host in ["rydr-backend-2cl9.onrender.com", "rydr-stripe-backend.onrender.com", "rydr-bank.onrender.com"] {
            let base = try #require(URL(string: "https://\(host)"))
            let relative = try #require(URL(string: "/cash-hub/access/accept?source=terms", relativeTo: base))
            let request = RydrWorkspace.urlRequest(url: relative)
            let result = try #require(request.url)
            #expect(result.scheme == "https")
            #expect(result.host == host)
            #expect(result.path == "/workspaces/\(workspace)/cash-hub/access/accept")
            #expect(result.query == "source=terms")
            #expect(result.baseURL == nil)
            #expect(RydrWorkspace.scopedURL(result) == result)
        }
    }

    @Test func bootstrapAndExternalURLsRemainUnchanged() throws {
        let base = try #require(URL(string: "https://rydr-stripe-backend.onrender.com"))
        for path in ["/workspace-bootstrap", "/account-config"] {
            let url = try #require(URL(string: path, relativeTo: base))
            #expect(RydrWorkspace.scopedURL(url).absoluteURL == url.absoluteURL)
        }
        let external = try #require(URL(string: "https://example.com/help"))
        #expect(RydrWorkspace.scopedURL(external) == external)
    }
}

struct CardSaveAttemptTests {
    @Test func repeatedTapsAndNetworkRetriesKeepOneSaveAttempt() {
        var attempt = CardSaveAttempt()
        let id = attempt.begin()
        #expect(id != nil)
        #expect(attempt.begin() == nil)
        #expect(attempt.begin() == nil)
        attempt.failed()
        #expect(attempt.begin() == id)
        attempt.confirmed("seti_fixture")
        attempt.failed()
        #expect(attempt.begin() == id)
        #expect(attempt.confirmedIntentID == "seti_fixture")
        attempt.succeeded()
        #expect(attempt.begin() == nil)
    }
}

struct CardSaveRecoveryTests {
    @Test func interruptedSaveSurvivesReopeningAndIsIsolatedByAccount() {
        let scope = "test:" + UUID().uuidString
        var first = CardSaveAttempt()
        first.bind(scope: scope)
        let id = first.begin()
        first.confirmed("seti_saved")
        first.failed()
        var reopened = CardSaveAttempt()
        reopened.bind(scope: scope)
        #expect(reopened.begin() == id)
        #expect(reopened.confirmedIntentID == "seti_saved")
        reopened.failed()
        reopened.bind(scope: scope + ":different-account")
        #expect(reopened.confirmedIntentID == nil)
        #expect(reopened.begin() != id)
        reopened.succeeded()
        first.succeeded()
    }
    @Test func retryPolicyDoesNotRetryDeclinesOrClientCancellation() {
        #expect(CardSaveTransport.isTransient(URLError(.networkConnectionLost), status: nil))
        #expect(CardSaveTransport.isTransient(nil, status: 503))
        #expect(CardSaveTransport.isTransient(URLError(.networkConnectionLost), status: 200))
        #expect(!CardSaveTransport.isTransient(URLError(.cancelled), status: 503))
        #expect(!CardSaveTransport.isTransient(nil, status: 402))
        #expect(!CardSaveTransport.isTransient(URLError(.cancelled), status: nil))
    }
}

private final class InterruptedCardSaveProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bodies: [Data?] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; bodies = [] }
    static var captured: [Data?] { lock.lock(); defer { lock.unlock() }; return bodies }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        Self.lock.lock()
        Self.bodies.append(body)
        let first = Self.bodies.count == 1
        Self.lock.unlock()
        if first { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct CardSaveTransportRecoveryTests {
    @Test func lostResponseRetriesTheSameIdempotentPayload() async throws {
        InterruptedCardSaveProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InterruptedCardSaveProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://card-save.invalid/create-setup-intent")!)
        request.httpMethod = "POST"
        let body = Data("{\"requestId\":\"same-attempt\"}".utf8)
        request.httpBody = body
        let status: Int = try await withCheckedThrowingContinuation { continuation in
            CardSaveTransport.perform(request, retryable: true, session: session) { _, response, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode ?? 0) }
            }
        }
        #expect(status == 200)
        #expect(InterruptedCardSaveProtocol.captured.count == 2)
        #expect(InterruptedCardSaveProtocol.captured.allSatisfy { $0 == body })
    }
}
