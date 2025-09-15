import Foundation
import CryptoKit

/// `DataHasher` は、データの暗号学的ハッシュを計算するためのユーティリティを提供します。
///
/// この構造体は、与えられた `Data` オブジェクトに対して SHA-256 ハッシュを計算するための静的メソッドを提供します。
/// SHA-256 は、256ビット（32バイト）のハッシュ値を生成する、広く使用されている暗号学的ハッシュ関数です。
/// これは、データの整合性チェック、データの一意な識別子の作成、またはその他のセキュリティ関連タスクに役立ちます。
struct DataHasher {
    /// 与えられたデータの SHA-256 ハッシュを計算します。
    ///
    /// このメソッドは `Data` オブジェクトを入力として受け取り、`CryptoKit` フレームワークを使用してその SHA-256 ハッシュを計算し、
    /// ハッシュを16進数の文字列として返します。結果の文字列は小文字です。
    ///
    /// - Parameter data: ハッシュ化する `Data` オブジェクト。
    /// - Returns: 16進数形式の SHA-256 ハッシュを表す文字列。
    static func computeSHA256(for data: Data) -> String {
        // CryptoKit の SHA256 を使用してハッシュダイジェストを計算します。
        let digest = SHA256.hash(data: data)

        // ダイジェストを16進数の文字列表現に変換します。
        // ダイジェストの各バイトは、2桁の16進数（例：「0f」、「a9」）としてフォーマットされます。
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
