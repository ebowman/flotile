// Minimal dependency ported from GateOpener (https://github.com/ebowman/gateopener, MIT)
// ComelitAPITests.swift; the Comelit OAuth `state` echo machinery is omitted.
import Foundation

/// A `URLProtocol` that serves canned responses for offline testing, keyed by
/// request path suffix. No live network calls are made.
///
/// Because swift-testing runs `@Test` functions concurrently by default, stub
/// registrations are scoped per test via a unique `X-Test-Run-Id` header
/// injected by `makeStubbedSession(runId:)`, rather than shared global state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let status: Int
        let headers: [String: String]
        let body: Data
        let responseURL: URL?

        init(status: Int, headers: [String: String] = [:], body: Data, responseURL: URL? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
            self.responseURL = responseURL
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlersByRun: [String: [(String, Stub)]] = [:]

    static let runIdHeader = "X-Test-Run-Id"

    static func addHandler(runId: String, pathSuffix: String, stub: Stub) {
        lock.lock()
        handlersByRun[runId, default: []].append((pathSuffix, stub))
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let runId = request.value(forHTTPHeaderField: StubURLProtocol.runIdHeader) ?? ""
        let path = request.url?.path ?? ""

        StubURLProtocol.lock.lock()
        let match = StubURLProtocol.handlersByRun[runId]?.first(where: { path.hasSuffix($0.0) })
        StubURLProtocol.lock.unlock()

        guard let (_, stub) = match else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: stub.responseURL ?? request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Build a `URLSession` that routes through `StubURLProtocol` and tags every
/// outgoing request with a unique run id.
func makeStubbedSession(runId: String = UUID().uuidString) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    config.httpAdditionalHeaders = [StubURLProtocol.runIdHeader: runId]
    return URLSession(configuration: config)
}
