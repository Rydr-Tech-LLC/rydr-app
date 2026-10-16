import Foundation
import Testing
@testable import RydrPlayground

struct RydrPlaygroundTests {
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
