import SwiftUI

struct ChatMessageUiItem: Identifiable {
    let id: String
    let text: String
    let isUser: Bool
    let timeFormatted: String
    let richInsight: RichInsightUiItem?
}

struct RichInsightUiItem {
    let title: String
    let mainStat: String
    let subtitle: String
}

struct AssistantView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var isRecording: Bool = false

    @State private var messages: [ChatMessageUiItem] = [
        ChatMessageUiItem(
            id: "1",
            text: "Hello! I'm your Sanvya AI financial assistant. Ask me anything about your spending, splits, budgets, or net worth.",
            isUser: false,
            timeFormatted: "10:14 AM",
            richInsight: nil
        ),
        ChatMessageUiItem(
            id: "2",
            text: "How much did I spend on dining out this month?",
            isUser: true,
            timeFormatted: "10:15 AM",
            richInsight: nil
        ),
        ChatMessageUiItem(
            id: "3",
            text: "You've spent ₹6,400 on Food & Dining in July 2026 across 14 transactions. That's 80% of your ₹8,000 monthly dining budget.",
            isUser: false,
            timeFormatted: "10:15 AM",
            richInsight: RichInsightUiItem(
                title: "Monthly Dining Budget Status",
                mainStat: "₹6,400 / ₹8,000",
                subtitle: "80% used • 5 days remaining in period"
            )
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(messages) { msg in
                            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(msg.text)
                                        .font(.subheadline)
                                        .foregroundColor(msg.isUser ? Color.surface : Color.text)

                                    if let insight = msg.richInsight {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(insight.title)
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(Color.text2)
                                            Text(insight.mainStat)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(Color.accent)
                                            Text(insight.subtitle)
                                                .font(.caption2)
                                                .foregroundColor(Color.text)
                                        }
                                        .padding(10)
                                        .background(Color.surface2)
                                        .cornerRadius(10)
                                    }
                                }
                                .padding(14)
                                .background(msg.isUser ? Color.accent : Color.surface)
                                .cornerRadius(16)
                                .frame(maxWidth: 280, alignment: msg.isUser ? .trailing : .leading)

                                Text(msg.timeFormatted)
                                    .font(.caption2)
                                    .foregroundColor(Color.text2)
                            }
                            .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
                        }
                    }
                    .padding(16)
                }

                // Composer bar
                HStack(spacing: 10) {
                    Button(action: { isRecording.toggle() }) {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isRecording ? .white : Color.text)
                            .frame(width: 40, height: 40)
                            .background(isRecording ? Color.accent : Color.surface2)
                            .clipShape(Circle())
                    }

                    TextField("Ask Sanvya AI…", text: $inputText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.surface)
                        .cornerRadius(20)

                    Button(action: {
                        if !inputText.isEmpty {
                            messages.append(
                                ChatMessageUiItem(
                                    id: UUID().uuidString,
                                    text: inputText,
                                    isUser: true,
                                    timeFormatted: "Just now",
                                    richInsight: nil
                                )
                            )
                            inputText = ""
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.surface)
                            .frame(width: 40, height: 40)
                            .background(Color.accent)
                            .clipShape(Circle())
                    }
                }
                .padding(12)
                .background(Color.surface)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("✨ Sanvya AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }
}

#Preview {
    AssistantView()
}
