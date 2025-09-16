import Foundation
import CoreGraphics // For CGRect

// MARK: - UI Data Models

/*
 NOTE: These data models (`MangaPage`, `Bubble`) are designed for use within the UI layer (e.g., SwiftUI views).
 They are distinct from the Core Data managed objects (`Page`, `BubbleEntity`).
 注：これらのデータモデル（`MangaPage`、`Bubble`）は、UI層（例：SwiftUIビュー）内で使用するために設計されています。
 これらはCore Dataのマネージドオブジェクト（`Page`、`BubbleEntity`）とは異なります。

 This separation is an intentional architectural choice (a pattern sometimes called "ViewModel" or "UI Model"):
 この分離は意図的なアーキテクチャ上の選択（「ViewModel」や「UIモデル」と呼ばれるパターン）です：
 - UI models can be structs, which are safer and easier to reason about in SwiftUI.
   UIモデルは構造体（struct）にでき、SwiftUIにおいてより安全で理解しやすくなります。
 - They can be tailored specifically to the needs of the view, containing only the necessary data in the right format.
   ビューのニーズに合わせて特化させ、必要なデータのみを適切な形式で含めることができます。
 - It decouples the UI from the persistence layer (Core Data). Changes to the database schema
   don't automatically break the UI, and vice-versa.
   UIを永続化層（Core Data）から分離します。データベーススキーマの変更が自動的にUIを壊すことはなく、その逆も同様です。
 - They are not tied to a Core Data context and can be passed around freely.
   Core Dataコンテキストに束縛されず、自由に受け渡しできます。
*/


/// Represents a single page of a manga, serving as a data model for the UI.
/// 漫画の単一ページを表し、UIのデータモデルとして機能します。
///
/// This struct holds all information related to a page that the UI needs to display,
/// including the source image URL and any detected text bubbles.
/// この構造体は、UIが表示する必要のあるページ関連のすべての情報（ソース画像のURLや検出されたフキダシなど）を保持します。
struct MangaPage: Identifiable, Equatable {
    /// A stable, unique identifier for the page, derived from the absolute string of the source URL.
    /// ページの安定した一意な識別子。ソースURLの絶対文字列から派生します。
    var id: String { sourceURL.absoluteString }

    /// The URL of the original image file for this page.
    /// このページの元の画像ファイルのURL。
    let sourceURL: URL

    /// An array of text bubbles detected within this page.
    /// このページ内で検出されたフキダシの配列。
    var bubbles: [Bubble] = []

    /// The current processing status of this page.
    /// このページの現在の処理状態。
    var status: ProcessingStatus = .pending

    // Conformance to Equatable is based on the unique ID.
    // Equatableへの準拠は、一意なIDに基づいています。
    static func == (lhs: MangaPage, rhs: MangaPage) -> Bool {
        lhs.id == rhs.id
    }
}

/// An enumeration describing the processing status of a manga page.
/// 漫画のページの処理状態を示す列挙型。
enum ProcessingStatus: Equatable {
    /// Not yet processed.
    /// 未処理。
    case pending
    /// Currently being processed (e.g., bubble detection or OCR is running).
    /// 現在処理中（例：フキダシ検出やOCRが実行中）。
    case processing
    /// Processing has completed successfully.
    /// 処理が正常に完了。
    case completed
    /// Processing failed with an associated error.
    /// 処理が関連するエラーで失敗。
    case failed(Error)

    // Custom implementation for Equatable conformance.
    // Equatable準拠のためのカスタム実装。
    static func == (lhs: ProcessingStatus, rhs: ProcessingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.processing, .processing),
             (.completed, .completed):
            return true
        case let (.failed(lhsError), .failed(rhsError)):
            // For simplicity, we compare the localized descriptions of the errors.
            // A more robust implementation might compare error codes or domains.
            // 簡単のため、エラーのローカライズされた説明を比較します。
            // より堅牢な実装では、エラーコードやドメインを比較するかもしれません。
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Represents the information for a single text bubble within a page.
/// ページ内の単一のフキダシに関する情報を表します。
struct Bubble: Identifiable, Equatable {
    /// A unique identifier for this specific bubble instance.
    /// この特定のフキダシインスタンスのための一意な識別子。
    let id = UUID()

    /// The position and size of the bubble within its parent image, represented by a `CGRect`.
    /// 親画像内でのフキダシの位置とサイズ。`CGRect`で表されます。
    let rect: CGRect

    /// The original text as recognized by the OCR engine.
    /// OCRエンジンによって認識された元のテキスト。
    var originalText: String

    /// The translated text. This is optional as translation may not have occurred yet.
    /// 翻訳されたテキスト。翻訳がまだ行われていない場合があるため、オプショナルです。
    var translatedText: String?
}
