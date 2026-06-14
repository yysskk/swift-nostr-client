import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A minimal `URLProtocol` that returns a canned response, for mocking the LNURL HTTP call.
///
/// `NostrClientTests` has its own URL mock, but it lives in a different test target, so this module
/// carries a small one. Suites that use it must be `.serialized` because the canned response is
/// shared static state.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var statusCode = 200

    /// A `URLSession` configured to route all requests through this protocol.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)
        {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
