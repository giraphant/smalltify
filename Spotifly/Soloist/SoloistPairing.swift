//
//  SoloistPairing.swift
//  Spotifly
//
//  Signs Soloist in with this app's own login, as an official app does when it is chosen.
//

import CommonCrypto
import CryptoKit
import Foundation

/// Signs Soloist in with this app's login: what an official Spotify app does when Soloist is
/// chosen in its device list, which is Spotify Connect's ZeroConf `addUser`.
///
/// Soloist runs a small HTTP server for it at `/zc`. `getInfo` gives its device id and a
/// Diffie-Hellman public key; `addUser` takes the account's login in a blob only that device can
/// open: encrypted for its device id, then for the key the two sides agree on. librespot's
/// discovery server opens the same blob (`discovery/src/server.rs` and
/// `core/src/authentication.rs`), which is where the layout comes from.
///
/// The login is the reusable credential Spotify gave this app's own accesspoint session
/// (`StoredCredentialsStore`), so Soloist joins the account this app is signed in to.
nonisolated enum SoloistPairing {
    /// What `getInfo` says of the device.
    struct Info: Decodable, Equatable {
        let deviceID: String
        let publicKey: String
        let remoteName: String
        let version: String?
        let tokenType: String?
    }

    enum Failure: LocalizedError, Equatable {
        case notReached
        case unsupported(String)
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .notReached: String(localized: "soloist.error.not_reached")
            case let .unsupported(tokenType): String(localized: "soloist.error.unsupported \(tokenType)")
            case let .refused(status): String(localized: "soloist.error.refused \(status)")
            }
        }
    }

    /// Signs the Soloist named `deviceName` in. Its pairing server listens beside its WebSocket;
    /// Soloist names only the WebSocket's port, so the ones around it are asked which is the
    /// server and which device it is.
    static func pair(nextTo socketPort: UInt16, deviceName: String, login: StoredLogin,
                     session: URLSession) async throws {
        let (endpoint, info) = try await find(nextTo: socketPort, deviceName: deviceName, session: session)
        // `default` is the blob exchange below; the token kinds some devices ask for instead
        // need a token minted for the device, which this app has no way to get.
        guard info.tokenType == nil || info.tokenType == "default" else {
            throw Failure.unsupported(info.tokenType ?? "")
        }
        guard let remoteKey = Data(base64Encoded: info.publicKey) else { throw Failure.notReached }
        let keys = try DiffieHellman()
        var iv = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv) == errSecSuccess else { throw Failure.notReached }
        let blob = try Self.blob(login: login, deviceID: info.deviceID,
                                 sharedSecret: keys.exchange(remotePublicKeyBytes: remoteKey), iv: Data(iv))
        let fields = [
            ("action", "addUser"), ("version", info.version ?? "2.10.0"), ("tokenType", "default"),
            ("clientKey", keys.publicKeyBytes.base64EncodedString()), ("loginId", ""),
            ("userName", login.username), ("blob", blob),
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(fields).utf8)
        debugLog("Soloist", "[POST] zeroconf addUser")
        let (data, _) = try await session.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // 101 is ZeroConf's OK; anything else names what went wrong.
        guard answer?["status"] as? Int == 101 else {
            throw Failure.refused(answer?["statusString"] as? String ?? String(answer?["status"] as? Int ?? 0))
        }
    }

    /// The pairing server of the Soloist named `deviceName`, and what it says of itself.
    private static func find(nextTo socketPort: UInt16, deviceName: String,
                             session: URLSession) async throws -> (URL, Info) {
        // Soloist binds its two ports one after the other, so the server has always sat on the
        // next one; the rest are there in case another bind came between.
        let candidates = [Int(socketPort) + 1] + (Int(socketPort) - 4 ... Int(socketPort) + 8)
            .filter { $0 != Int(socketPort) && $0 != Int(socketPort) + 1 }
        for port in candidates where (1 ... 65535).contains(port) {
            guard let url = URL(string: "http://127.0.0.1:\(port)/zc") else { continue }
            var request = URLRequest(url: url.appending(queryItems: [.init(name: "action", value: "getInfo")]),
                                     timeoutInterval: 2)
            request.httpMethod = "GET"
            guard let (data, _) = try? await session.data(for: request),
                  let info = try? JSONDecoder().decode(Info.self, from: data),
                  info.remoteName == deviceName else { continue }
            return (url, info)
        }
        throw Failure.notReached
    }

    /// `application/x-www-form-urlencoded`, escaping everything but the unreserved characters,
    /// as base64's `+` and `/` would otherwise be read as a space and a separator.
    static func formEncoded(_ fields: [(String, String)]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
        }.joined(separator: "&")
    }

    // MARK: - The blob

    /// The `blob` field: the login encrypted for the device (`innerBlob`), as base64 text, then
    /// AES-128-CTR under a key from the Diffie-Hellman secret, behind its IV and followed by an
    /// HMAC-SHA1 of the ciphertext, all in base64.
    static func blob(login: StoredLogin, deviceID: String, sharedSecret: Data, iv: Data) throws -> String {
        let baseKey = Data(Insecure.SHA1.hash(data: sharedSecret)).prefix(16)
        let encryptionKey = Data(HMAC<Insecure.SHA1>.authenticationCode(
            for: Data("encryption".utf8), using: SymmetricKey(data: baseKey))).prefix(16)
        let checksumKey = Data(HMAC<Insecure.SHA1>.authenticationCode(
            for: Data("checksum".utf8), using: SymmetricKey(data: baseKey)))
        let inner = try innerBlob(login: login, deviceID: deviceID).base64EncodedData()
        let encrypted = try aes(CCMode(kCCModeCTR), key: Data(encryptionKey), iv: iv, data: inner)
        let checksum = Data(HMAC<Insecure.SHA1>.authenticationCode(for: encrypted, using: SymmetricKey(data: checksumKey)))
        return (iv + encrypted + checksum).base64EncodedString()
    }

    /// The login as `Credentials::with_blob` reads it: a tag, the username, a tag, the auth
    /// type, a tag, the auth data, padded to whole blocks; then each byte from the 17th XORed
    /// with the one 16 before it, as already changed; then AES-192-ECB under a key from the
    /// device id and the username.
    static func innerBlob(login: StoredLogin, deviceID: String) throws -> Data {
        var plain = [UInt8]()
        func int(_ value: Int) {
            if value < 0x80 {
                plain.append(UInt8(value))
            } else {
                plain.append(UInt8(0x80 | (value & 0x7F)))
                plain.append(UInt8(value >> 7))
            }
        }
        func bytes(_ data: Data) {
            int(data.count)
            plain.append(contentsOf: data)
        }
        int(0x49)
        bytes(Data(login.username.utf8))
        int(0x50)
        int(Int(login.authType))
        int(0x51)
        bytes(login.authData)
        let zeros = 16 - plain.count % 16 - 1
        plain.append(contentsOf: [UInt8](repeating: 0, count: zeros))
        plain.append(UInt8(zeros + 1))
        for index in 16 ..< plain.count {
            plain[index] ^= plain[index - 16]
        }
        return try aes(CCMode(kCCModeECB), key: blobKey(deviceID: deviceID, username: login.username), iv: nil, data: Data(plain))
    }

    /// SHA-1 of PBKDF2-HMAC-SHA1 (256 rounds) of the device id's SHA-1, salted with the
    /// username, and then the length 20 as four big-endian bytes: a 24-byte key.
    static func blobKey(deviceID: String, username: String) throws -> Data {
        let secret = Data(Insecure.SHA1.hash(data: Data(deviceID.utf8)))
        let salt = Data(username.utf8)
        var derived = [UInt8](repeating: 0, count: 20)
        let status = secret.withUnsafeBytes { secretBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     secretBytes.baseAddress?.assumingMemoryBound(to: CChar.self), secret.count,
                                     saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 0x100, &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { throw Failure.notReached }
        return Data(Insecure.SHA1.hash(data: Data(derived))) + Data([0, 0, 0, 20])
    }

    /// One pass of AES in `mode`, without padding: the data is whole blocks for ECB, and CTR
    /// needs none.
    static func aes(_ mode: CCMode, key: Data, iv: Data?, data: Data) throws -> Data {
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            (iv ?? Data()).withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), mode, CCAlgorithm(kCCAlgorithmAES),
                                        CCPadding(ccNoPadding), iv == nil ? nil : ivBytes.baseAddress,
                                        keyBytes.baseAddress, key.count, nil, 0, 0, 0, &cryptor)
            }
        }
        guard status == kCCSuccess, let cryptor else { throw Failure.notReached }
        defer { CCCryptorRelease(cryptor) }
        var output = Data(count: data.count)
        var moved = 0
        let update = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                CCCryptorUpdate(cryptor, input.baseAddress, data.count, out.baseAddress, data.count, &moved)
            }
        }
        guard update == kCCSuccess, moved == data.count else { throw Failure.notReached }
        return output
    }
}
