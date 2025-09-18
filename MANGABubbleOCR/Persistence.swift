import CoreData

/// `PersistenceController` is a struct that encapsulates the Core Data stack for the application.
/// `PersistenceController`は、アプリケーションのCore Dataスタックをカプセル化する構造体です。
///
/// It follows a singleton pattern (`shared`) to provide a single point of access to the Core Data container.
/// This simplifies the management of the data model, context, and store coordinator.
/// シングルトンパターン（`shared`）に従い、Core Dataコンテナへの単一のアクセスポイントを提供します。
/// これにより、データモデル、コンテキスト、およびストアコーディネーターの管理が簡素化されます。
struct PersistenceController {

    /// The shared singleton instance of the persistence controller.
    /// 永続化コントローラーの共有シングルトンインスタンス。
    static let shared = PersistenceController()

    /// The persistent container for the application, which encapsulates the Core Data stack.
    /// アプリケーションの永続コンテナ。Core Dataスタックをカプセル化します。
    let container: NSPersistentContainer

    /// Initializes the persistence controller.
    /// 永続化コントローラーを初期化します。
    ///
    /// - Parameter inMemory: A boolean value that determines whether the data should be stored
    ///   in memory or on disk. If `true`, the data is stored in a temporary, in-memory database,
    ///   which is useful for previews or unit tests. Defaults to `false`.
    /// - Parameter inMemory: データをメモリに保存するかディスクに保存するかを決定するブール値。
    ///   `true`の場合、データは一時的なインメモリデータベースに保存され、プレビューや単体テストに役立ちます。
    ///   デフォルトは`false`です。
    init(inMemory: Bool = false) {
        // Initialize the container with the name of the data model file ("MANGABubbleOCR.xcdatamodeld").
        // データモデルファイルの名前（"MANGABubbleOCR.xcdatamodeld"）でコンテナを初期化します。
        container = NSPersistentContainer(name: "MANGABubbleOCR")

        if inMemory {
            // If in-memory storage is requested, configure the persistent store to be written to /dev/null.
            // This effectively creates a temporary, memory-only database that is discarded when the app closes.
            // インメモリでの保存が要求された場合、永続ストアを/dev/nullに書き込むように構成します。
            // これにより、アプリ終了時に破棄される一時的なメモリのみのデータベースが効果的に作成されます。
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Load the persistent stores (e.g., the SQLite database from disk).
        // This is an asynchronous operation.
        // 永続ストア（例：ディスクからのSQLiteデータベース）をロードします。
        // これは非同期操作です。
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
                // これは開発中の致命的なエラーです。
                // ここでのエラーの典型的な理由には以下が含まれます：
                // * 親ディレクトリが存在しない、作成できない、または書き込みが許可されていない。
                // * デバイスがロックされているときに、権限やデータ保護のために永続ストアにアクセスできない。
                // * デバイスの空き容量が不足している。
                // * ストアを現在のモデルバージョンに移行できなかった。
                //
                // 製品版アプリケーションでは、このエラーはユーザーに警告するか、データベースのリセットを試みるなど、
                // 優雅に処理する必要があります。
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })

        // Configure the main view context to automatically merge changes saved on background contexts.
        // This is crucial for updating the UI when data is processed and saved in the background,
        // as is done by the `ImageViewerModel`.
        // メインビューコンテキストがバックグラウンドコンテキストで保存された変更を自動的にマージするように構成します。
        // これは、`ImageViewerModel`で行われるように、データがバックグラウンドで処理・保存されたときに
        // UIを更新するために不可欠です。
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Deletes all data from the Core Data store.
    /// Core Dataストアからすべてのデータを削除します。
    ///
    /// This method uses `NSBatchDeleteRequest` to efficiently remove all objects
    /// for the `Book`, `Page`, and `BubbleEntity` entities.
    /// このメソッドは`NSBatchDeleteRequest`を使用して、`Book`、`Page`、および`BubbleEntity`エンティティの
    /// すべてのオブジェクトを効率的に削除します。
    func deleteAllData() {
        // An array of entity names to be deleted.
        // 削除するエンティティ名の配列。
        let entityNames = ["Book", "Page", "BubbleEntity"]

        // Get the managed object context from the container.
        // コンテナから管理オブジェクトコンテキストを取得します。
        let context = container.viewContext

        // Iterate over the entity names and perform a batch delete for each.
        // エンティティ名を反復処理し、それぞれに対してバッチ削除を実行します。
        entityNames.forEach { entityName in
            // Create a fetch request for the entity.
            // エンティティのフェッチリクエストを作成します。
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entityName)

            // Create a batch delete request with the fetch request.
            // フェッチリクエストを使用してバッチ削除リクエストを作成します。
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            // Set the result type to notify the context of the object IDs that were deleted.
            // This is important for the UI to update correctly after the deletion.
            deleteRequest.resultType = .resultTypeObjectIDs

            do {
                // Execute the batch delete request and get the result.
                // バッチ削除リクエストを実行し、結果を取得します。
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult

                // Get the array of managed object IDs that were deleted.
                // 削除された管理オブジェクトIDの配列を取得します。
                guard let objectIDs = result?.result as? [NSManagedObjectID] else { return }

                // Create a dictionary with the deleted object IDs to merge the changes
                // into the managed object context.
                // 削除されたオブジェクトIDで辞書を作成し、変更を管理オブジェクトコンテキストに
                // マージします。
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])

            } catch let error as NSError {
                // Handle any errors that occur during the batch delete.
                // In a real application, this should be handled more gracefully.
                // バッチ削除中に発生したエラーを処理します。
                // 実際のアプリケーションでは、これをより優雅に処理する必要があります。
                print("Could not batch delete \(entityName). \(error), \(error.userInfo)")
            }
        }
    }
}
