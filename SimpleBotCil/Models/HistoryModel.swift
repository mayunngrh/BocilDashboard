import Foundation

struct AudioHistoryItem: Identifiable {
    let id = UUID()
    var title: String
    let date: String
    let time: String
    let duration: String
    let bars: [CGFloat]
}

enum HistoryFilter: Equatable {
    case allTime
    case day(String)
}
