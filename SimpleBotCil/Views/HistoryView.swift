import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    @State private var editMode = false
    @State private var selectedConversation: Conversation? = nil

    // "Pick Date" popover state
    @State private var showDatePicker = false
    @State private var pickedDate = Date()

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

            HStack(spacing: 8) {
                filterChip(label: "This Week", isSelected: vm.filter == .thisWeek) {
                    vm.filter = .thisWeek
                }

                pickDateChip

                Button(action: { editMode.toggle() }) {
                    Text(editMode ? "Done" : "Edit")
                        .font(Bocil.mono(14))
                        .foregroundColor(editMode ? Bocil.ink : Bocil.subtext)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(editMode ? Bocil.accentSoft : Color.white)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - "This Week" grouped content

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

    // MARK: - "Pick Date" content

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
    // Keeps the original card design (play glyph, waveform, title, time,
    // duration). The whole card opens the chat detail; Edit mode swaps in
    // rename + delete affordances.

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        Button(action: { if !editMode { selectedConversation = conversation } }) {
            HStack(spacing: 16) {
                Text("▶")
                    .font(.system(size: 12))
                    .foregroundColor(Bocil.accent)
                    .frame(width: 36, height: 36)
                    .background(Bocil.bg)
                    .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 2))

                WaveformView(bars: WaveformView.mockBars(seed: conversation.id.hashValue))

                VStack(alignment: .leading, spacing: 4) {
                    if editMode {
                        TextField("Title", text: Binding(
                            get: { conversation.title },
                            set: { vm.rename(conversation, to: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(Bocil.mono(16))
                        .foregroundColor(Bocil.ink)
                        .padding(4)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
                    } else {
                        Text(conversation.title)
                            .font(Bocil.mono(16))
                            .foregroundColor(Bocil.ink)
                    }
                    Text("\(conversation.startTimeLabel) · \(conversation.messages.count) voice messages")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.faint)
                }

                Spacer()

                if editMode {
                    Button("Delete") { vm.delete(conversation) }
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.danger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
                        .buttonStyle(.plain)
                } else {
                    Text(conversation.durationLabel)
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.subtext)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter controls

    @ViewBuilder
    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Bocil.mono(14))
                .foregroundColor(isSelected ? Bocil.ink : Bocil.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Bocil.accentSoft : Color.white)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var pickDateChip: some View {
        let isPicked: Bool = { if case .day = vm.filter { return true }; return false }()
        let label: String = {
            if case .day(let d) = vm.filter { return Self.shortDate(d) }
            return "Pick Date ▾"
        }()

        return Button(action: { showDatePicker.toggle() }) {
            Text(label)
                .font(Bocil.mono(14))
                .foregroundColor(isPicked ? Bocil.ink : Bocil.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isPicked ? Bocil.accentSoft : Color.white)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
            // Native monthly calendar with month + year switching.
            DatePicker("", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .onChange(of: pickedDate) { _, newValue in
                    vm.filter = .day(newValue)
                    showDatePicker = false
                }
        }
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
