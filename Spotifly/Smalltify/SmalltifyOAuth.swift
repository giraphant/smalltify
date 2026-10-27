/// Dashboard's current HTTP validator requires an explicit port, despite the docs
/// permitting portless loopback registrations. Keep setup and the listener in sync.
nonisolated enum SmalltifyOAuth {
    static let callbackPort: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:\(callbackPort)/login"
}
