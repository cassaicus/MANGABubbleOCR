import SwiftUI
import Vision
import CoreML
import CoreData

/**
 `ImageViewerModel` is the primary ViewModel that manages the application's UI state and data flow for manga viewing and analysis.

 This class is responsible for:
 - Holding the list of `MangaPage` objects to be displayed.
 - Tracking the current page index.
 - Interacting with Core Data to persist and retrieve manga, page, and text bubble information.
 - Orchestrating the bubble detection process using the Vision framework.
 - Coordinating with `OCREngine` to perform text recognition on detected bubbles.

 It is implemented as a singleton to provide a single, shared instance across the entire application.
 UI updates are triggered using `@Published` properties, which notify SwiftUI views of any changes.
*/
class ImageViewerModel: ObservableObject {

    // MARK: - Singleton Instance

    /// The shared singleton instance of `ImageViewerModel`.
    static let shared = ImageViewerModel()
    
    // MARK: - Published Properties

    /// The array of all manga pages currently loaded.
    /// Changes to this array will trigger UI updates in subscribed SwiftUI views.
    @Published var pages: [MangaPage] = []

    /// The index of the currently displayed page within the `pages` array.
    @Published var currentIndex: Int = 0

    // MARK: - Core Components

    /// The main-thread `NSManagedObjectContext` for all Core Data operations.
    private let viewContext = PersistenceController.shared.container.viewContext

    /// A reference to the OCR engine.
    private let ocrEngine: OCREngine

    // MARK: - Constants

    private enum Constants {
        static let bubbleDetectorModelName = "best"
        static let bubbleDetectorModelExtension = "mlmodelc"
        static let croppedBubblesDirectory = "cropped_bubbles"
        static let ocrEngineIdentifier = "MangaOCR-v1.0"
        static let ocrEngineIdentifierRetry = "MangaOCR-v1.0-retry"
    }

    // MARK: - Initialization

    /// Private initializer to enforce the singleton pattern.
    ///
    /// This attempts to initialize the `OCREngine`. If the engine fails to load
    /// (e.g., model or vocabulary file is missing), the application will terminate
    /// with a fatal error, as OCR is a critical feature.
    private init() {
        do {
            self.ocrEngine = try OCREngine()
        } catch {
            // In a production app, you might want to handle this more gracefully,
            // for example, by disabling OCR-related features in the UI.
            fatalError("ImageViewerModel: Failed to initialize OCREngine. Error: \(error)")
        }
    }

    // MARK: - Public Methods for Page Management

    /// Updates the model with a new list of pages.
    /// - Parameter newPages: The new array of `MangaPage` objects to display.
    func setPages(_ newPages: [MangaPage]) {
        self.pages = newPages
        self.currentIndex = 0
        let urls = newPages.map { $0.sourceURL }
        // Start prefetching thumbnails for the new pages in the background.
        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
    }

    /// Asynchronously loads images from a specified folder URL and updates the pages list.
    /// - Parameter folder: The URL of the folder containing the image files.
    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            let newPages = urls.map { MangaPage(sourceURL: $0) }
            DispatchQueue.main.async {
                self?.setPages(newPages)
            }
        }
    }

    /// Displays a folder selection dialog and loads the images from the chosen folder.
    func selectAndLoadFolder() {
        // Cancel any ongoing prefetching before loading a new folder.
        ThumbnailPrefetcher.shared.cancelAll()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    // MARK: - Bubble Analysis and OCR Orchestration

    /// Initiates the text bubble analysis for the currently displayed image.
    func analyzeCurrentImageForTextBubbles() {
        guard currentIndex < pages.count else { return }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        Task {
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let cgImage = nsImage.cgImage(),
                  let imageData = nsImage.tiffRepresentation else {
                print("Error: Failed to load image or convert it to data for analysis.")
                return
            }
            // Hand off to the Vision request performer.
            performVisionRequest(with: cgImage, imageData: imageData, originalFileName: imageURL.lastPathComponent)
        }
    }

    /// Performs a Vision request to detect text bubbles in the given image.
    ///
    /// This method uses a pre-trained Core ML model (`best.mlmodelc`) to find objects
    /// that are classified as text bubbles. The results are then passed to the saving logic.
    private func performVisionRequest(with cgImage: CGImage, imageData: Data, originalFileName: String) {
        guard let modelURL = Bundle.main.url(forResource: Constants.bubbleDetectorModelName, withExtension: Constants.bubbleDetectorModelExtension) else {
            print("Error: Bubble detector model file not found.")
            return
        }

        do {
            let vnModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
                if let error = error {
                    print("Vision request failed: \(error.localizedDescription)")
                    return
                }
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    print("Vision request completed but returned no results or an unexpected type.")
                    return
                }
                self?.processVisionResults(results, forImage: cgImage, imageData: imageData, originalFileName: originalFileName)
            }
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])
        } catch {
            print("Error: Failed to load VNCoreMLModel or perform request: \(error.localizedDescription)")
        }
    }
    
    /// Processes the results from the Vision request, creating and saving bubble entities.
    ///
    /// This method orchestrates the entire process of saving bubble data:
    /// 1. Sets up a temporary directory for cropped bubble images.
    /// 2. Uses a `DispatchGroup` to coordinate multiple asynchronous OCR tasks.
    /// 3. Performs all Core Data operations on the correct `viewContext` queue.
    /// 4. Fetches or creates the `Page` entity for the image.
    /// 5. Deletes any old bubbles associated with the page.
    /// 6. Iterates through detected bubbles, creating `BubbleEntity` objects and dispatching OCR tasks.
    /// 7. Saves the Core Data context once all OCR tasks are complete.
    private func processVisionResults(_ results: [VNRecognizedObjectObservation], forImage cgImage: CGImage, imageData: Data, originalFileName: String) {
        let ocrDispatchGroup = DispatchGroup()

        // All subsequent Core Data operations must be on the context's queue.
        viewContext.perform {
            let page = self.fetchOrCreatePage(with: DataHasher.computeSHA256(for: imageData), originalFileName: originalFileName)
            
            // Clear out any previously detected bubbles for this page.
            if let existingBubbles = page.bubbles as? NSSet {
                existingBubbles.forEach { self.viewContext.delete($0 as! NSManagedObject) }
            }
            
            // Process each detected bubble.
            for observation in results {
                self.createAndProcessBubble(
                    from: observation,
                    in: cgImage,
                    page: page,
                    dispatchGroup: ocrDispatchGroup
                )
            }

            // After all OCR tasks have been dispatched, set up a notification
            // to save the context to disk when they all complete.
            ocrDispatchGroup.notify(queue: .main) {
                self.saveContext()
            }
        }
    }

    /// Creates a single `BubbleEntity`, crops its image, and dispatches an OCR task.
    private func createAndProcessBubble(from observation: VNRecognizedObjectObservation, in cgImage: CGImage, page: Page, dispatchGroup: DispatchGroup) {
        let newBubble = BubbleEntity(context: self.viewContext)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let rect = observation.boundingBox.toPixelRectFlipped(in: imageSize)

        newBubble.bubbleID = UUID()
        newBubble.x = rect.origin.x
        newBubble.y = rect.origin.y
        newBubble.width = rect.size.width
        newBubble.height = rect.size.height
        newBubble.page = page
        newBubble.shouldOcr = true
        newBubble.ocrStatus = "pending"

        guard newBubble.shouldOcr, let croppedCGImage = cgImage.cropping(to: rect) else {
            newBubble.ocrStatus = "skipped"
            return
        }

        // Dispatch an asynchronous OCR task for the cropped image.
        dispatchGroup.enter()
        runOCR(on: croppedCGImage, for: newBubble.objectID) {
            dispatchGroup.leave()
        }
    }

    /// Performs OCR on a single cropped image and updates the corresponding `BubbleEntity`.
    ///
    /// This method includes a retry mechanism: if OCR fails with the primary normalization
    /// method, it attempts again with a secondary method.
    private func runOCR(on cgImage: CGImage, for bubbleObjectID: NSManagedObjectID, completion: @escaping () -> Void) {
        // OCR is computationally expensive, so it's run on a background thread.
        DispatchQueue.global(qos: .userInitiated).async {
            var ocrResult: (text: String, identifier: String)
            
            do {
                // 1. First attempt with the primary normalization.
                let text = try self.ocrEngine.recognizeText(from: cgImage, normalization: .scaleTo_minus1_1)
                ocrResult = (text, Constants.ocrEngineIdentifier)
            } catch {
                print("OCR failed with primary normalization, retrying... Error: \(error)")
                do {
                    // 2. Second attempt with the fallback normalization.
                    let text = try self.ocrEngine.recognizeText(from: cgImage, normalization: .scaleTo_0_1)
                    ocrResult = (text, Constants.ocrEngineIdentifierRetry)
                } catch {
                    print("OCR failed with secondary normalization. Error: \(error)")
                    ocrResult = ("[\(error.localizedDescription)]", "failure")
                }
            }

            // 3. Update the Core Data object on its own context's queue.
            self.viewContext.perform {
                self.updateBubble(bubbleObjectID, with: ocrResult)
                completion()
            }
        }
    }
    
    /// Updates a `BubbleEntity` with the results of an OCR operation.
    /// This method must be called on the `viewContext`'s queue.
    private func updateBubble(_ bubbleObjectID: NSManagedObjectID, with result: (text: String, identifier: String)) {
        guard let bubble = try? self.viewContext.existingObject(with: bubbleObjectID) as? BubbleEntity else {
            return
        }

        let isSuccess = result.identifier != "failure"

        bubble.ocrText = result.text
        bubble.ocrTimestamp = Date()
        bubble.ocrEngineIdentifier = result.identifier
        bubble.ocrConfidence = isSuccess ? 1.0 : 0.0 // Placeholder confidence
        bubble.ocrStatus = isSuccess ? "success" : "failure"

        print("OCR Result for bubble [\(bubble.bubbleID!)] with engine [\(result.identifier)]: \(result.text)")
    }

    // MARK: - Core Data Helper Methods

    /// Fetches a `Page` entity with a specific hash from Core Data, or creates one if not found.
    /// This method must be called on the `viewContext`'s queue.
    private func fetchOrCreatePage(with hash: String, originalFileName: String) -> Page {
        let request: NSFetchRequest<Page> = Page.fetchRequest()
        request.predicate = NSPredicate(format: "fileHash == %@", hash)
        
        if let existingPage = try? viewContext.fetch(request).first {
            return existingPage
        }
        
        let newPage = Page(context: viewContext)
        newPage.pageID = UUID()
        newPage.fileHash = hash
        newPage.originalFileName = originalFileName
        newPage.book = fetchOrCreateBook() // Associate with a book
        return newPage
    }

    /// Fetches the first `Book` entity or creates a default one if none exist.
    /// This method must be called on the `viewContext`'s queue.
    private func fetchOrCreateBook() -> Book {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.fetchLimit = 1
        
        if let existingBook = try? viewContext.fetch(request).first {
            return existingBook
        }
        
        let newBook = Book(context: viewContext)
        newBook.bookID = UUID()
        newBook.title = "Default Book"
        return newBook
    }

    /// Saves the Core Data context if there are changes.
    private func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            print("Successfully saved bubbles and OCR results to Core Data.")
        } catch {
            print("Failed to save Core Data context: \(error.localizedDescription)")
            // Rollback to discard the failed changes.
            viewContext.rollback()
        }
    }

}
