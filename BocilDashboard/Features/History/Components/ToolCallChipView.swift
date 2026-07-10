import SwiftUI

/// Small inline chip shown between a turn's user/assistant bubbles when the
/// model made a tool lookup (calendar, tasks, web search) while answering.
struct ToolCallChipView: View {
    let call: ConversationToolCall

    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12))
            Text(call.label)
                .font(Bocil.mono(11))
                .foregroundColor(Bocil.ink)
            if let summary = call.summary, !summary.isEmpty {
                Text("· \(summary)")
                    .font(Bocil.mono(11))
                    .foregroundColor(Bocil.subtext)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(borderColor, lineWidth: 1.5))
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var icon: String {
        switch call.tool {
        case "calendar": return "📅"
        case "tasks": return "☑︎"
        case "web_search": return "🔎"
        case "persona": return "🎭"
        case "emotion": return "🙂"
        case "move": return "🤖"
        default: return "⚙︎"
        }
    }

    private var borderColor: Color {
        switch call.status {
        case "error": return Bocil.danger
        case "duplicate": return Bocil.faint
        default: return Bocil.cardBorder
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        ToolCallChipView(call: ConversationToolCall(
            id: "1", tool: "calendar", action: "list", label: "list",
            status: "success", summary: "Found 2 event(s).", createdAt: Date()
        ))
        ToolCallChipView(call: ConversationToolCall(
            id: "2", tool: "tasks", action: "create", label: "create: Buy milk",
            status: "duplicate", summary: "Already looked that up this turn.", createdAt: Date()
        ))
        ToolCallChipView(call: ConversationToolCall(
            id: "3", tool: "web_search", action: nil, label: "weather in Bali",
            status: "error", summary: "Request timed out.", createdAt: Date()
        ))
    }
    .padding()
    .background(Bocil.bg)
}
