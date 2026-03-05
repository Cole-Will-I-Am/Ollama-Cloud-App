import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var selection: Conversation?
    @State private var showModelPicker = false
    @State private var pendingConversation: Conversation?

    var body: some View {
        List(selection: $selection) {
            ForEach(conversations) { conversation in
                NavigationLink(value: conversation) {
                    HStack(spacing: 14) {
                        // Model icon
                        ZStack {
                            Circle()
                                .fill(Color.surfaceElevated)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(Color.border, lineWidth: 0.5)
                                )
                            Image(systemName: "cpu")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(Color.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                if !conversation.modelName.isEmpty {
                                    Text(conversation.modelName)
                                        .font(.caption2)
                                        .foregroundStyle(Color.accent.opacity(0.8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.accent.opacity(0.1))
                                        )
                                }
                                Spacer()
                                Text(conversation.updatedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    newConversation()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView { model in
                if let conv = pendingConversation {
                    conv.modelName = model.name
                    try? modelContext.save()
                    selection = conv
                }
                showModelPicker = false
            }
        }
        .overlay {
            if conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Color.textTertiary)
                    Text("No conversations yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                    Text("Tap + to start")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary.opacity(0.6))
                }
            }
        }
    }

    private func newConversation() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        pendingConversation = conversation
        showModelPicker = true
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = conversations[index]
            if selection?.id == conversation.id {
                selection = nil
            }
            modelContext.delete(conversation)
        }
        try? modelContext.save()
    }
}
