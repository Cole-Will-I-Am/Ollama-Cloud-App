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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversation.title)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        HStack {
                            if !conversation.modelName.isEmpty {
                                Text(conversation.modelName)
                                    .font(.caption)
                                    .foregroundStyle(Color.accent)
                            }
                            Spacer()
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    newConversation()
                } label: {
                    Image(systemName: "plus")
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
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left")
                } description: {
                    Text("Tap + to start a new chat.")
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
