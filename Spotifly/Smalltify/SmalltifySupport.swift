import Foundation

nonisolated struct SmalltifyError: LocalizedError {
    /// What the interface can offer besides the message: a reauthorization, a wait.
    enum Reason: Sendable, Equatable {
        case other
        case signedOut
        case authExpired
        case forbidden
        case rateLimited(seconds: Int)
    }

    let message: String
    var reason = Reason.other
    init(_ message: String, reason: Reason = .other) {
        self.message = message
        self.reason = reason
    }

    var errorDescription: String? { message }
}

nonisolated enum SmalltifySecrets {
    static let service = "io.github.giraphant.smalltify.official.v1"

    static func save(_ data: Data, key: String) throws {
        try KeychainManager.save(key: key, data: data, service: service)
    }

    static func load(_ key: String) -> Data? {
        KeychainManager.load(key: key, service: service)
    }

    static func delete(_ key: String) {
        KeychainManager.delete(key: key, service: service)
    }
}

/// Never follow a server-controlled redirect carrying an OAuth header or token body.
nonisolated final class SmalltifyHTTPDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: SmalltifyHTTPDelegate(), delegateQueue: nil)
    }
}
