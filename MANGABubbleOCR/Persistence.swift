import CoreData

/// `PersistenceController` is a struct that encapsulates the Core Data stack for the application.
///
/// It follows a singleton pattern (`shared`) to provide a single point of access to the Core Data container.
/// This simplifies the management of the data model, context, and store coordinator.
struct PersistenceController {

    /// The shared singleton instance of the persistence controller.
    static let shared = PersistenceController()

    /// The persistent container for the application, which encapsulates the Core Data stack.
    let container: NSPersistentContainer

    /// Initializes the persistence controller.
    ///
    /// - Parameter inMemory: A boolean value that determines whether the data should be stored
    ///   in memory or on disk. If `true`, the data is stored in a temporary, in-memory database,
    ///   which is useful for previews or unit tests. Defaults to `false`.
    init(inMemory: Bool = false) {
        // Initialize the container with the name of the data model file ("MANGABubbleOCR.xcdatamodeld").
        container = NSPersistentContainer(name: "MANGABubbleOCR")

        if inMemory {
            // If in-memory storage is requested, configure the persistent store to be written to /dev/null.
            // This effectively creates a temporary, memory-only database that is discarded when the app closes.
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Load the persistent stores (e.g., the SQLite database from disk).
        // This is an asynchronous operation.
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // This is a critical error during development.
                // Typical reasons for an error here include:
                // * The parent directory does not exist, cannot be created, or disallows writing.
                // * The persistent store is not accessible due to permissions or data protection when the device is locked.
                // * The device is out of space.
                // * The store could not be migrated to the current model version.
                //
                // In a shipping application, this error should be handled gracefully, perhaps by
                // alerting the user or attempting to reset the database.
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })

        // Configure the main view context to automatically merge changes saved on background contexts.
        // This is crucial for updating the UI when data is processed and saved in the background,
        // as is done by the `ImageViewerModel`.
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
