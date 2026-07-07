import Foundation

/// Filter applied to the history list.
/// - `thisWeek`: grouped-by-day view for the current week (default).
/// - `day`: only conversations from a single picked date.
enum HistoryFilter: Equatable {
    case thisWeek
    case day(Date)
}

/// One dated group of conversations shown in the "This Week" view,
/// e.g. "Today", "Yesterday" or "Saturday 4/7".
struct ConversationSection: Identifiable {
    let title: String
    let date: Date
    let conversations: [Conversation]

    /// Stable identity: the section's day. A random UUID here would give every
    /// recompute a new identity, tearing down child views (and breaking
    /// TextField focus while renaming).
    var id: Date { date }
}
