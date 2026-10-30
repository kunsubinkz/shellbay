import Foundation
import CommonCrypto
import CryptoKit

public struct PinHasher {
    public static func hash(pin: String, salt: Data, rounds: UInt32 = 120_000) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pin.utf8)
        pw.withUnsafeBufferPointer { pwp in
            salt.withUnsafeBytes { sp in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), UnsafeRawPointer(pwp.baseAddress!).assumingMemoryBound(to: Int8.self), pw.count,
                                         sp.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &out, 32)
            }
        }
        return Data(out)
    }
}

public final class PinStore: @unchecked Sendable {
    private let store: SecretStore
    public init(store: SecretStore) { self.store = store }
    public var isSet: Bool { store.get(service: SecretService.pin, account: "pin") != nil }
    public static func isValidPin(_ s: String) -> Bool { s.count == 4 && s.allSatisfy(\.isNumber) }

    public func setPin(_ pin: String) throws {
        precondition(Self.isValidPin(pin))
        var salt = Data(count: 16); _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let h = PinHasher.hash(pin: pin, salt: salt)
        try store.set(salt.base64EncodedString() + ":" + h.base64EncodedString(), service: SecretService.pin, account: "pin")
    }
    public func verify(_ pin: String) -> Bool {
        guard let v = store.get(service: SecretService.pin, account: "pin") else { return false }
        let p = v.split(separator: ":").map(String.init)
        guard p.count == 2, let salt = Data(base64Encoded: p[0]), let expect = Data(base64Encoded: p[1]) else { return false }
        return PinHasher.hash(pin: pin, salt: salt) == expect
    }
    public func clear() { store.delete(service: SecretService.pin, account: "pin") }
}
