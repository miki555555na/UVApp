import SwiftUI
import CoreData

struct UVHistoryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UVRecord.timestamp, ascending: false)],
        animation: .default)
    private var records: FetchedResults<UVRecord>

    var body: some View {
        List {
            ForEach(records) { record in
                VStack(alignment: .leading) {
                    Text("Time: \(record.timestamp ?? Date(), formatter: dateFormatter)")
                    Text("UV Out: \(record.uvOut)")
                    Text("UV In: \(record.uvIn)")
                }
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

