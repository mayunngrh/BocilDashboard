import Foundation
import Combine
import SwiftUI

/// Loads and organizes chat history for `HistoryView`.
///
/// The ViewModel owns all presentation logic (grouping by day, filtering by a
/// picked date) and reads its data from a `ConversationRepository`. Swap the
/// repository in `init` to move from mock data to the real backend.
@MainActor
final class HistoryViewModel: ObservableObject {

    @Published private(set) var conversations: [Conversation] = []
    @Published var filter: HistoryFilter = .thisWeek
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository: ConversationRepository
    private let calendar = Calendar.current

    init(repository: ConversationRepository = APIConversationRepository()) {
        self.repository = repository
    }

    /// Fetches conversations from the repository. Call from `.task` and from
    /// the error banner's retry button.
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            conversations = try await repository.fetchConversations()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - "This Week" grouped view

    /// Conversations from the last 7 days, grouped by day and ordered
    /// newest → oldest. Each section carries a human header ("Today",
    /// "Yesterday", or the weekday + date). `locale` comes from the calling
    /// view's `@Environment(\.locale)` — this ViewModel isn't a View, so it
    /// can't read the environment override itself.
    func weekSections(locale: Locale) -> [ConversationSection] {
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }

        let recent = conversations.filter { $0.createdAt >= cutoff }
        let groups = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.createdAt) }

        return groups.keys.sorted(by: >).map { dayStart in
            let items = (groups[dayStart] ?? []).sorted { $0.createdAt > $1.createdAt }
            return ConversationSection(
                title: sectionTitle(for: dayStart, locale: locale),
                date: dayStart,
                conversations: items
            )
        }
    }

    // MARK: - "Pick Date" view

    /// Conversations that happened on the given day, newest first.
    func conversations(on date: Date) -> [Conversation] {
        conversations
            .filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Editing (kept so the list's Edit mode keeps working)

    /// Renames a conversation. Clearing the field stores `nil`, which makes the
    /// UI fall back to the date-based placeholder title.
    func rename(_ conversation: Conversation, to title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        let isBlank = title.trimmingCharacters(in: .whitespaces).isEmpty
        conversations[idx].title = isBlank ? nil : title
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
    }

    // MARK: - Helpers

    /// "Today" / "Yesterday" / "Saturday 4/7" header for a day.
    private func sectionTitle(for day: Date, locale: Locale) -> String {
        if calendar.isDateInToday(day) { return String(localized: "common.today", locale: locale) }
        if calendar.isDateInYesterday(day) { return String(localized: "common.yesterday", locale: locale) }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EEEE d/M"
        return f.string(from: day)
    }
}
