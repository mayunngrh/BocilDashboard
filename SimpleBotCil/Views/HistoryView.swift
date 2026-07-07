import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    @State private var selectedConversation: Conversation? = nil

    // Filter dropdown state
    @State private var filterOpen = false
    @State private var showCalendar = false

    // Per-row title editing state
    @State private var editingID: UUID? = nil
    @State private var draftTitle = ""
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        Group {
            if let conversation = selectedConversation {
                ConversationDetailView(conversation: conversation) {
                    selectedConversation = nil
                }
            } else {
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await vm.load() }
    }

    // MARK: - History list

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .zIndex(1)

                switch vm.filter {
                case .thisWeek: weekContent
                case .day(let date): dayContent(date)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
    }

    private var header: some View {
        HStack {
            Text("CHAT HISTORY")
                .font(Bocil.header(32))
                .foregroundColor(Bocil.ink)

            Spacer()

            filterButton
        }
    }

    // MARK: - Filter button + dropdown

    private var filterLabel: String {
        switch vm.filter {
        case .thisWeek: return "This week"
        case .day(let d): return Self.shortDate(d)
        }
    }

    private var filterButton: some View {
        Button(action: {
            showCalendar = false
            filterOpen.toggle()
        }) {
            Text("Filter: \(filterLabel) ▾")
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
        .buttonStyle(.plain)
        // Popover lives in its own window, so calendar taps are never swallowed
        // by the list underneath (which an inline overlay suffered from).
        .popover(isPresented: $filterOpen, arrowEdge: .bottom) {
            dropdownContent
                .background(Color.white)
        }
    }

    @ViewBuilder
    private var dropdownContent: some View {
        if showCalendar {
            // Mini calendar styled after the Calendar page; picking a day applies
            // the filter and closes the dropdown.
            MiniCalendarView(selectedDate: pickedDate) { date in
                vm.filter = .day(date)
                closeDropdown()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                dropdownRow(label: "This week", isSelected: vm.filter == .thisWeek) {
                    vm.filter = .thisWeek
                    closeDropdown()
                }
                dropdownRow(label: "Pick date", isSelected: pickedDate != nil) {
                    showCalendar = true
                }
            }
            .frame(width: 160)
        }
    }

    @ViewBuilder
    private func dropdownRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Bocil.bg : Color.white)
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(Bocil.bg).frame(height: 1), alignment: .bottom)
    }

    private var pickedDate: Date? {
        if case .day(let d) = vm.filter { return d }
        return nil
    }

    private func closeDropdown() {
        filterOpen = false
        showCalendar = false
    }

    // MARK: - "This week" grouped content

    @ViewBuilder
    private var weekContent: some View {
        let sections = vm.weekSections
        if sections.isEmpty {
            emptyState("No conversations this week")
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(Bocil.header(16))
                            .foregroundColor(Bocil.subtext)

                        VStack(spacing: 12) {
                            ForEach(section.conversations) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - "Pick date" content

    @ViewBuilder
    private func dayContent(_ date: Date) -> some View {
        let items = vm.conversations(on: date)
        if items.isEmpty {
            emptyState("No conversations on \(Self.longDate(date))")
        } else {
            VStack(spacing: 12) {
                ForEach(items) { conversation in
                    conversationRow(conversation)
                }
            }
        }
    }

    // MARK: - Conversation card
    // The card itself is a tap target (opens the chat detail); the play and
    // pencil controls are separate buttons layered on top. Keeping the card
    // out of a `Button` wrapper lets the inline TextField receive focus.

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        let isEditing = editingID == conversation.id

        HStack(spacing: 16) {
            Text("▶")
                .font(.system(size: 12))
                .foregroundColor(Bocil.accent)
                .frame(width: 36, height: 36)
                .background(Bocil.bg)
                .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 2))

            WaveformView(bars: WaveformView.mockBars(seed: conversation.id.hashValue))

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(conversation.displayTitle, text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(Bocil.mono(16))
                        .foregroundColor(Bocil.ink)
                        .focused($titleFieldFocused)
                        .onSubmit { commitEdit(conversation) }
                        .padding(4)
                        .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 1.5))
                } else {
                    Text(conversation.displayTitle)
                        .font(Bocil.mono(16))
                        .foregroundColor(conversation.title == nil ? Bocil.subtext : Bocil.ink)
                }
                Text("\(conversation.startTimeLabel) · \(conversation.messages.count) voice messages")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.faint)
            }

            Spacer()

            if isEditing {
                Button("Save") { commitEdit(conversation) }
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Bocil.accentSoft)
                    .buttonStyle(.plain)

                Button("Delete") {
                    vm.delete(conversation)
                    editingID = nil
                }
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
                .buttonStyle(.plain)
            } else {
                // Small pencil: puts just this card into title-edit mode.
                Button(action: { beginEdit(conversation) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Bocil.subtext)
                        .frame(width: 26, height: 26)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Bocil.hairline, lineWidth: 1.5))
                }
                .buttonStyle(.plain)

                Text(conversation.durationLabel)
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.subtext)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white)
        .overlay(Rectangle().stroke(isEditing ? Bocil.accentSoft : Bocil.cardBorder, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { selectedConversation = conversation }
        }
    }

    // MARK: - Title editing

    private func beginEdit(_ conversation: Conversation) {
        editingID = conversation.id
        draftTitle = conversation.title ?? ""
        titleFieldFocused = true
    }

    private func commitEdit(_ conversation: Conversation) {
        vm.rename(conversation, to: draftTitle)
        editingID = nil
        draftTitle = ""
    }

    // MARK: - Empty state

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("⌾")
                .font(.system(size: 34))
                .foregroundColor(Bocil.faint)
            Text(message)
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.faint)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240)
    }

    // MARK: - Date formatting helpers

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static func longDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

#Preview {
    HistoryView().frame(width: 1000, height: 700)
}
