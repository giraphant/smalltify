import CommonCrypto
import CryptoKit
import Foundation
@testable import Spotifly
import Testing

/// The blob is checked against the device side of the exchange, written here the way librespot
/// reads it (`discovery/src/server.rs` `handle_add_user`, `core/src/authentication.rs`
/// `Credentials::with_blob`): if this decoder gets the login back, a device that decodes the
/// same way does too.
struct SoloistPairingTests {
    let login = StoredLogin(username: "31uhs5qiw6bvec7yhx3uy3lfngxa",
                            authData: Data((0 ..< 180).map { UInt8($0 & 0xFF) }), authType: 1)
    let deviceID = "9037f659-ad71-4304-8e21-7b1bb5a18b4e"

    @Test func `a device decoding the blob as librespot does gets the login back`() throws {
        let sharedSecret = Data((1 ... 96).map { UInt8($0) })
        let iv = Data(repeating: 7, count: 16)
        let blob = try SoloistPairing.blob(login: login, deviceID: deviceID, sharedSecret: sharedSecret, iv: iv)

        let decoded = try Self.decode(blob: blob, sharedSecret: sharedSecret, username: login.username, deviceID: deviceID)

        #expect(decoded.username == login.username)
        #expect(decoded.authType == login.authType)
        #expect(decoded.authData == login.authData)
    }

    @Test func `a blob for another device does not open`() throws {
        let sharedSecret = Data((1 ... 96).map { UInt8($0) })
        let blob = try SoloistPairing.blob(login: login, deviceID: deviceID, sharedSecret: sharedSecret,
                                           iv: Data(repeating: 1, count: 16))

        let decoded = try? Self.decode(blob: blob, sharedSecret: sharedSecret, username: login.username, deviceID: "another")

        #expect(decoded?.authData != login.authData)
    }

    @Test func `the two sides of the key exchange agree`() throws {
        let ours = try DiffieHellman()
        let theirs = try DiffieHellman()

        #expect(ours.exchange(remotePublicKeyBytes: theirs.publicKeyBytes)
            == theirs.exchange(remotePublicKeyBytes: ours.publicKeyBytes))
    }

    @Test func `base64 survives the form encoding`() {
        let encoded = SoloistPairing.formEncoded([("blob", "ab+c/d=="), ("loginId", "")])

        #expect(encoded == "blob=ab%2Bc%2Fd%3D%3D&loginId=")
    }

    // MARK: - The device side

    private struct Decoded {
        let username: String
        let authType: UInt32
        let authData: Data
    }

    private enum DecodeError: Error { case checksum, layout }

    private static func decode(blob: String, sharedSecret: Data, username: String, deviceID: String) throws -> Decoded {
        let signed = try #require(Data(base64Encoded: blob))
        let iv = signed.prefix(16)
        let encrypted = signed.dropFirst(16).dropLast(20)
        let checksum = signed.suffix(20)
        let baseKey = Data(Insecure.SHA1.hash(data: sharedSecret)).prefix(16)
        let checksumKey = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data("checksum".utf8), using: SymmetricKey(data: baseKey)))
        let encryptionKey = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data("encryption".utf8), using: SymmetricKey(data: baseKey))).prefix(16)
        guard Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(encrypted), using: SymmetricKey(data: checksumKey))) == checksum else {
            throw DecodeError.checksum
        }
        // CTR decrypts by encrypting again.
        let text = try SoloistPairing.aes(CCMode(kCCModeCTR), key: Data(encryptionKey), iv: Data(iv), data: Data(encrypted))
        var data = try [UInt8](#require(Data(base64Encoded: text)))
        data = try [UInt8](decryptECB(Data(data), key: SoloistPairing.blobKey(deviceID: deviceID, username: username)))
        let count = data.count
        for index in 0 ..< count - 0x10 {
            data[count - index - 1] ^= data[count - index - 0x11]
        }
        var cursor = 0
        func byte() throws -> UInt8 {
            guard cursor < data.count else { throw DecodeError.layout }
            defer { cursor += 1 }
            return data[cursor]
        }
        func int() throws -> UInt32 {
            let low = try UInt32(byte())
            guard low & 0x80 != 0 else { return low }
            return try low & 0x7F | UInt32(byte()) << 7
        }
        func bytes() throws -> Data {
            let length = try Int(int())
            guard cursor + length <= data.count else { throw DecodeError.layout }
            defer { cursor += length }
            return Data(data[cursor ..< cursor + length])
        }
        _ = try byte()
        let name = try String(decoding: bytes(), as: UTF8.self)
        _ = try byte()
        let authType = try int()
        _ = try byte()
        let authData = try bytes()
        return Decoded(username: name, authType: authType, authData: authData)
    }

    private static func decryptECB(_ data: Data, key: Data) throws -> Data {
        var output = Data(count: data.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, key.count, nil, input.baseAddress, data.count,
                            out.baseAddress, data.count, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.layout }
        return output
    }
}
