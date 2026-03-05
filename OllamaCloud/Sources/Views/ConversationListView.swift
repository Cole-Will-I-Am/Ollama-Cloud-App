import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var selection: Conversation?
    @State private var showModelPicker = false
    @State private var pendingConversation: Conversation?
    @State private var persistenceError: String?

    private var sortedConversations: [Conversation] {
        conversations.sorted {
            let lhsPinned = $0.isPinned == true
            let rhsPinned = $1.isPinned == true
            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sortedConversations) { conversation in
                NavigationLink(value: conversation) {
                    HStack(spacing: 14) {
                        // Avatar
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentSoft)
                                .frame(width: 40, height: 40)
                            Image(systemName: "cpu")
                                .font(.system(size: 15, weight: .ultraLight))
                                .foregroundStyle(Color.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(conversation.title)
                                    .font(.app(15, weight: .regular))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                if conversation.isPinned == true {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.accent)
                                }
                            }

                            HStack(spacing: 6) {
                                if !conversation.modelName.isEmpty {
                                    Text(conversation.modelName.uppercased())
                                        .font(.appLabel(9))
                                        .luxuryTracking()
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        togglePin(conversation)
                    } label: {
                        Label(conversation.isPinned == true ? "Unpin" : "Pin", systemImage: conversation.isPinned == true ? "pin.slash" : "pin")
                    }
                    .tint(Color.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteConversation(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
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
                        .font(.system(size: 16, weight: .ultraLight))
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
                    do {
                        try modelContext.save()
                        selection = conv
                    } catch {
                        persistenceError = "Failed to save model selection."
                    }
                }
                showModelPicker = false
            }
        }
        .alert("Storage Error", isPresented: Binding(
            get: { persistenceError != nil },
            set: { _ in persistenceError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown storage error occurred.")
        }
        .overlay {
            if conversations.isEmpty {
                VStack(spacing: 14) {
                    Image("SeerEmblem")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 48)
                    Text("Let's Party")
                        .font(.app(15, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private func newConversation() {
        Haptic.impact()
        let conversation = Conversation()
        modelContext.insert(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to save new conversation."
            modelContext.delete(conversation)
            return
        }
        pendingConversation = conversation
        showModelPicker = true
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = sortedConversations[index]
            if selection?.id == conversation.id { selection = nil }
            modelContext.delete(conversation)
        }
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete conversation."
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selection?.id == conversation.id { selection = nil }
        modelContext.delete(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete conversation."
        }
    }

    private func togglePin(_ conversation: Conversation) {
        conversation.isPinned = !(conversation.isPinned == true)
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to update chat pin."
        }
    }
}
