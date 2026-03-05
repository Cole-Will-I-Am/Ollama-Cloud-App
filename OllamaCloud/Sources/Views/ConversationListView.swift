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
                        // Avatar
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentSoft)
                                .frame(width: 40, height: 40)
                            Image(systemName: "cpu")
                                .font(.system(size: 15, weight: .light, design: .rounded))
                                .foregroundStyle(Color.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                if !conversation.modelName.isEmpty {
                                    Text(conversation.modelName)
                                        .font(.app(11))
                                        .foregroundStyle(Color.accent)
                                }
                                Spacer()
                                Text(conversation.updatedAt, style: .relative)
                                    .font(.app(11))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    newConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.accent)
                        .padding(8)
                        .background(
                            Circle().fill(Color.accentSoft)
                        )
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
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Color.textTertiary)
                    Text("No conversations")
                        .font(.app(15))
                        .foregroundStyle(Color.textTertiary)
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
            if selection?.id == conversation.id { selection = nil }
            modelContext.delete(conversation)
        }
        try? modelContext.save()
    }
}
