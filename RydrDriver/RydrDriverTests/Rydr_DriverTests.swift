import Foundation
import Testing
@testable import RydrDriver

struct Rydr_DriverTests {
    @Test func pendingIdentityAllowsOnboardingWithoutVerification() {
        let pending = DriverIdentityStatus(identityVerified: false, identityStatus: "processing")
        #expect(pending.canContinueOnboarding)
        #expect(!pending.isVerified)
        for value in ["requires_input", "canceled", "not_started", "pending", "unknown"] {
            let status = DriverIdentityStatus(identityVerified: false, identityStatus: value)
            #expect(!status.canContinueOnboarding)
            #expect(!status.isVerified)
        }
        #expect(DriverIdentityStatus(identityVerified: true, identityStatus: "verified").canContinueOnboarding)
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

struct DriverManagedPayoutConfigurationTests {
    @Test func managedAndLegacyAccountsRemainExplicit() throws {
        let managed = try JSONDecoder().decode(DriverPayoutSetupConfiguration.self, from: Data(#"{"managed":true,"requiresMigration":false,"mode":"test","workspace":"test"}"#.utf8))
        #expect(managed.managed)
        #expect(!managed.requiresMigration)
        let legacy = try JSONDecoder().decode(DriverPayoutSetupConfiguration.self, from: Data(#"{"managed":false,"requiresMigration":true,"mode":"live","workspace":"live-beta"}"#.utf8))
        #expect(!legacy.managed)
        #expect(legacy.requiresMigration)
        #expect(legacy.mode != managed.mode)
    }
}
