import Foundation

/// 漫画の1ページを表すデータモデル。
///
/// この構造体は、画像そのもののURLに加え、OCR結果や翻訳テキストなど、
/// ページに関連するすべての情報を保持します。
struct MangaPage: Identifiable, Equatable {
    /// 安定した一意なID。画像URLの絶対パスを使用します。
    var id: String { sourceURL.absoluteString }

    /// 元となる画像ファイルのURL。
    let sourceURL: URL

    /// ページ内で検出された吹き出しの配列。
    var bubbles: [Bubble] = []

    /// ページの処理状態。
    var status: ProcessingStatus = .pending

    // Equatableに準拠するため、idで比較します。
    static func == (lhs: MangaPage, rhs: MangaPage) -> Bool {
        lhs.id == rhs.id
    }
}

/// ページの処理状態を示すenum。
enum ProcessingStatus {
    case pending      // 未処理
    case processing   // 処理中
    case completed    // 処理完了
    case failed(Error) // 処理失敗

    // Equatableに準拠させるための実装。
    static func == (lhs: ProcessingStatus, rhs: ProcessingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.processing, .processing),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            // 本来はErrorの内容も比較すべきだが、ここでは簡略化
            return true
        default:
            return false
        }
    }
}

/// 1つの吹き出しに関する情報を表すデータモデル。
struct Bubble: Identifiable, Equatable {
    /// 構造体内で一意なID。
    let id = UUID()

    /// 画像内での吹き出しの位置（CGRect）。
    let rect: CGRect

    /// 元の言語のテキスト（OCR結果）。
    var originalText: String

    /// 翻訳後のテキスト。
    var translatedText: String?
}
