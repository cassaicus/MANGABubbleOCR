import Foundation
import CryptoKit

struct DataHasher {
    static func computeSHA256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
