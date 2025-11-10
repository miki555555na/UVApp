import CoreData

struct PersistenceController {
    //アプリ全体で一つのCoreDataを共有する
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    //データを永続化しない
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "UVModel") // .xcdatamodeld の名前
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        //上書きを許す
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

