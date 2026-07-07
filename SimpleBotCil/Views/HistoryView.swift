import SwiftUI

struct HistoryView: View {
    @State private var items: [AudioHistoryItem] = [
        AudioHistoryItem(title: "Morning check-in",      date: "Jul 3, 2026", time: "08:12 AM", duration: "0:42",
                         bars: [8,14,20,12,22,10,16,24,9,18,13,20,8,15,22,11,17,9]),
        AudioHistoryItem(title: "Focus session wrap-up", date: "Jul 2, 2026", time: "05:47 PM", duration: "1:15",
                         bars: [12,18,9,24,14,20,8,16,22,10,19,13,21,9,15,24,11,17]),
        AudioHistoryItem(title: "Untitled chat",         date: "Jul 1, 2026", time: "11:03 AM", duration: "0:28",
                         bars: [6,10,8,14,9,12,7,15,10,8,13,9,11,7,14,8,10,6]),
        AudioHistoryItem(title: "Weekend planning",      date: "Jun 29, 2026", time: "09:20 AM", duration: "2:03",
                         bars: [16,22,18,24,20,14,22,18,24,16,20,14,22,18,24,16,20,14]),
    ]

    @State private var filter: HistoryFilter = .allTime
    @State private var filterOpen = false
    @State private var editMode   = false
    @State private var playingID: UUID? = nil

    private var dateOptions: [String] {
        Array(NSOrderedSet(array: items.map { $0.date })) as! [String]
    }
    private var visibleItems: [AudioHistoryItem] {
        switch filter {
        case .allTime:    return items
        case .day(let d): return items.filter { $0.date == d }
        }
    }
    private var filterLabel: String {
        switch filter {
        case .allTime:    return "All time"
        case .day(let d): return d
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("CHAT HISTORY")
                        .font(Bocil.header(32))
                        .foregroundColor(Bocil.ink)

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: { filterOpen.toggle() }) {
                            Text("Filter: \(filterLabel) ▾")
                                .font(Bocil.mono(14))
                                .foregroundColor(Bocil.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Bocil.surface)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if filterOpen {
                                VStack(alignment: .leading, spacing: 0) {
                                    filterRow(label: "All time", isSelected: filter == .allTime) {
                                        filter = .allTime; filterOpen = false
                                    }
                                    ForEach(dateOptions, id: \.self) { d in
                                        filterRow(label: d, isSelected: filter == .day(d)) {
                                            filter = .day(d); filterOpen = false
                                        }
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .background(Bocil.surface)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
                                .offset(y: 38)
                            }
                        }

                        Button(action: { editMode.toggle() }) {
                            Text(editMode ? "Done" : "Edit")
                                .font(Bocil.mono(14))
                                .foregroundColor(editMode ? Bocil.ink : Bocil.subtext)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(editMode ? Bocil.accentSoft : Bocil.surface)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .zIndex(1)

                VStack(spacing: 12) {
                    ForEach(visibleItems) { item in
                        historyRow(item)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func historyRow(_ item: AudioHistoryItem) -> some View {
        HStack(spacing: 16) {
            Button(action: { playingID = (playingID == item.id) ? nil : item.id }) {
                Text(playingID == item.id ? "❚❚" : "▶")
                    .font(.system(size: 12))
                    .foregroundColor(Bocil.accent)
                    .frame(width: 36, height: 36)
                    .background(Bocil.bg)
                    .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 2))
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(item.bars.enumerated()), id: \.offset) { _, h in
                    Rectangle().fill(Bocil.cardBorder).frame(width: 3, height: h)
                }
            }
            .frame(height: 26, alignment: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                if editMode {
                    TextField("Title", text: Binding(
                        get: { item.title },
                        set: { newVal in
                            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                items[idx].title = newVal
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(Bocil.mono(16))
                    .foregroundColor(Bocil.ink)
                    .padding(4)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
                } else {
                    Text(item.title)
                        .font(Bocil.mono(16))
                        .foregroundColor(Bocil.ink)
                }
                Text("\(item.date) · \(item.time)")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.faint)
            }

            Spacer()

            if editMode {
                Button("Delete") {
                    items.removeAll { $0.id == item.id }
                }
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
                .buttonStyle(.plain)
            } else {
                Text(item.duration)
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.subtext)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
    }

    @ViewBuilder
    private func filterRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Bocil.bg : Bocil.surface)
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(Bocil.bg).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    HistoryView()
}
