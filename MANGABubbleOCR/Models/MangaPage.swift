import Foundation
import CoreGraphics // For CGRect

// MARK: - UI Data Models

/*
 NOTE: These data models (`MangaPage`, `Bubble`) are designed for use within the UI layer (e.g., SwiftUI views).
 They are distinct from the Core Data managed objects (`Page`, `BubbleEntity`).

 This separation is an intentional architectural choice (a pattern sometimes called "ViewModel" or "UI Model"):
 - UI models can be structs, which are safer and easier to reason about in SwiftUI.
 - They can be tailored specifically to the needs of the view, containing only the necessary data in the right format.
 - It decouples the UI from the persistence layer (Core Data). Changes to the database schema
   don't automatically break the UI, and vice-versa.
 - They are not tied to a Core Data context and can be passed around freely.
*/


/// Represents a single page of a manga, serving as a data model for the UI.
///
/// This struct holds all information related to a page that the UI needs to display,
/// including the source image URL and any detected text bubbles.
struct MangaPage: Identifiable, Equatable {
    /// A stable, unique identifier for the page, derived from the absolute string of the source URL.
    var id: String { sourceURL.absoluteString }

    /// The URL of the original image file for this page.
    let sourceURL: URL

    /// An array of text bubbles detected within this page.
    var bubbles: [Bubble] = []

    /// The current processing status of this page.
    var status: ProcessingStatus = .pending

    // Conformance to Equatable is based on the unique ID.
    static func == (lhs: MangaPage, rhs: MangaPage) -> Bool {
        lhs.id == rhs.id
    }
}

/// An enumeration describing the processing status of a manga page.
enum ProcessingStatus: Equatable {
    /// Not yet processed.
    case pending
    /// Currently being processed (e.g., bubble detection or OCR is running).
    case processing
    /// Processing has completed successfully.
    case completed
    /// Processing failed with an associated error.
    case failed(Error)

    // Custom implementation for Equatable conformance.
    static func == (lhs: ProcessingStatus, rhs: ProcessingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.processing, .processing),
             (.completed, .completed):
            return true
        case let (.failed(lhsError), .failed(rhsError)):
            // For simplicity, we compare the localized descriptions of the errors.
            // A more robust implementation might compare error codes or domains.
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Represents the information for a single text bubble within a page.
struct Bubble: Identifiable, Equatable {
    /// A unique identifier for this specific bubble instance.
    let id = UUID()

    /// The position and size of the bubble within its parent image, represented by a `CGRect`.
    let rect: CGRect

    /// The original text as recognized by the OCR engine.
    var originalText: String

    /// The translated text. This is optional as translation may not have occurred yet.
    var translatedText: String?
}
