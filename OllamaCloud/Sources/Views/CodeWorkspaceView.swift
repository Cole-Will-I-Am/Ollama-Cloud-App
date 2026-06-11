import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CodeWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var project: Project
    @State private var selectedFilePath: String?
    @State private var openFilePaths: [String] = []
    @State private var isChatPanelCollapsed = false
    @State private var sidebarWidth: CGFloat = 200
    @State private var chatPanelHeight: CGFloat = 250
    @State private var projectConversation: Conversation?
    @State private var showFileTreeSheet = false
    @State private var showChatSheet = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var persistenceError: String?
    @State private var showModelPicker = false
    @StateObject private var codeOutput = CodeBlockOutputState()
    @State private var saveBlock: ExtractedCodeBlock?

    private var selectedFile: ProjectFile? {
        guard let path = selectedFilePath else { return nil }
        return project.files.first { $0.path == path && !$0.isDirectory }
    }

    private var modelDisplayName: String {
        let name = projectConversation?.modelName ?? ""
        if name.isEmpty { return "No Model" }
        // Show just the model name portion (strip tag after colon if short enough)
        return name.count > 24 ? String(name.prefix(24)) + "..." : name
    }

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .toolbar {
            ToolbarItem(placement: .seerTrailing) {
                HStack(spacing: 12) {
                    Button { showModelPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 12, weight: .light))
                            Text(modelDisplayName)
                                .font(.appLabel(10))
                                .luxuryTracking()
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .macPointingCursor()
                    #endif

                    #if os(iOS)
                    // Compact layout only: in regular width (iPad) the file
                    // tree and chat panel are already embedded — these sheets
                    // would duplicate them (with a second streaming service).
                    if isCompact {
                        Button { showFileTreeSheet = true } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Button { showChatSheet = true } label: {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    #endif
                    Button { exportProject() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color.textSecondary)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .macPointingCursor()
                    #endif
                }
            }
        }
        .navigationTitle(project.name)
        #if os(macOS)
        .navigationSubtitle("\(project.files.filter { !$0.isDirectory }.count) files")
        #endif
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(onSelect: { model in
                if let conv = projectConversation {
                    conv.modelName = model.name
                    conv.apiProvider = model.provider
                    try? modelContext.save()
                }
                showModelPicker = false
            }, onCancel: {
                showModelPicker = false
            })
            .macSheetFixedSize(SeerSheetSize.modelPicker)
        }
        .alert("Error", isPresented: Binding(
            get: { persistenceError != nil },
            set: { _ in persistenceError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "")
        }
        .alert("Save Code Block", isPresented: Binding(
            get: { saveBlock != nil },
            set: { if !$0 { saveBlock = nil } }
        )) {
            Button("Save") {
                if let block = saveBlock {
                    saveBlockToFile(block)
                    saveBlock = nil
                }
            }
            Button("Cancel", role: .cancel) { saveBlock = nil }
        } message: {
            if let block = saveBlock {
                let ext = CodeLanguage.extensionForLanguage(block.language)
                Text("Save as \"untitled.\(ext)\"?")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showFileTreeSheet) {
            NavigationStack {
                fileTreeSidebar
                    .navigationTitle("Files")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFileTreeSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showChatSheet) {
            if let conversation = projectConversation {
                NavigationStack {
                    ProjectChatPanel(
                        conversation: conversation,
                        project: project,
                        isCollapsed: .constant(false),
                        codeOutput: codeOutput
                    )
                    .navigationTitle("Chat")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showChatSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        #endif
        .onAppear {
            loadProjectConversation()
            if openFilePaths.isEmpty, let first = project.files.first(where: { !$0.isDirectory }) {
                openFilePaths = [first.path]
                selectedFilePath = first.path
            }
        }
        .onChange(of: project.conversationID) {
            loadProjectConversation()
        }
        .onChange(of: project.updatedAt) {
            reconcileOpenTabs()
        }
        #if os(iOS)
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheetView(url: url)
            }
        }
        #endif
    }

    // MARK: - Regular Layout (macOS / iPad)

    private var regularLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // File tree sidebar
                fileTreeSidebar
                    .frame(width: sidebarWidth)

                // Vertical drag handle
                PanelDivider(axis: .vertical)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let new = sidebarWidth + value.translation.width
                                sidebarWidth = min(max(new, 120), 400)
                            }
                    )

                // Editor area
                VStack(spacing: 0) {
                    tabBar
                    Divider().background(Color.surface)
                    editorArea
                }
            }

            if let conversation = projectConversation {
                // Horizontal drag handle
                PanelDivider(axis: .horizontal)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let new = chatPanelHeight - value.translation.height
                                chatPanelHeight = min(max(new, 100), 600)
                                if isChatPanelCollapsed { isChatPanelCollapsed = false }
                            }
                    )

                ProjectChatPanel(
                    conversation: conversation,
                    project: project,
                    isCollapsed: $isChatPanelCollapsed,
                    codeOutput: codeOutput
                )
                .frame(height: isChatPanelCollapsed ? 30 : chatPanelHeight)
            }
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().background(Color.surface)
            editorArea
        }
    }

    // MARK: - File Tree Sidebar

    private var fileTreeSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FILES")
                    .font(.appLabel(10))
                    .luxuryTracking()
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Button { createNewFile(inDirectory: nil) } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.accent)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .macPointingCursor()
                #endif
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Color.surface)

            FileTreeView(
                files: project.files,
                selectedPath: $selectedFilePath,
                onDelete: { file in deleteFile(file) },
                onRename: { file, newName in renameFile(file, to: newName) },
                onNewFile: { dir in createNewFile(inDirectory: dir) }
            )
            .onChange(of: selectedFilePath) { _, newPath in
                if let newPath, !openFilePaths.contains(newPath) {
                    if project.files.contains(where: { $0.path == newPath && !$0.isDirectory }) {
                        openFilePaths.append(newPath)
                    }
                }
                #if os(iOS)
                showFileTreeSheet = false
                #endif
            }
        }
        .background(Color.bgSecondary)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openFilePaths, id: \.self) { path in
                    tabItem(path: path)
                }
            }
        }
        .frame(height: 32)
        .background(Color.bgSecondary)
    }

    private func tabItem(path: String) -> some View {
        let isSelected = selectedFilePath == path
        let name = path.split(separator: "/").last.map(String.init) ?? path

        return HStack(spacing: 4) {
            Text(name)
                .font(.app(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)

            Button {
                closeTab(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.bgPrimary : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedFilePath = path }
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        Group {
            if let file = selectedFile {
                let ext = file.path.split(separator: ".").last.map(String.init) ?? ""
                let lang = CodeLanguage.fromExtension(ext)
                CodeEditorView(
                    content: file.content,
                    language: lang,
                    onContentChange: { newContent in
                        file.content = newContent
                        file.updatedAt = Date()
                        project.updatedAt = Date()
                        try? modelContext.save()
                    }
                )
            } else if !codeOutput.allBlocks.isEmpty {
                CodeBlockOutputView(
                    blocks: codeOutput.allBlocks,
                    onSaveToFile: { block in
                        saveBlock = block
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Image("SeerEmblem")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .opacity(0.08)

                    Text(project.name)
                        .font(.appLabel(11))
                        .tracking(1.5)
                        .foregroundStyle(Color.textTertiary)

                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.3))
                        .frame(width: 40, height: 0.5)

                    #if os(macOS)
                    VStack(spacing: 8) {
                        shortcutRow(keys: "⌘N", label: "New File")
                        shortcutRow(keys: "⌘⇧N", label: "New Project")
                        shortcutRow(keys: "⌘/", label: "Toggle Chat")
                    }
                    #endif

                    Text("Select a file or ask the AI\nto start building")
                        .font(.app(12, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)
            }
        }
    }

    #if os(macOS)
    private func shortcutRow(keys: String, label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 40, alignment: .trailing)
            Text(label)
                .font(.app(12, weight: .light))
                .foregroundStyle(Color.textSecondary)
        }
    }
    #endif

    // MARK: - Actions

    private func closeTab(_ path: String) {
        openFilePaths.removeAll { $0 == path }
        if selectedFilePath == path {
            selectedFilePath = openFilePaths.last
        }
    }

    private func createNewFile(inDirectory: String?) {
        let basePath = inDirectory ?? ""
        let name = "untitled.txt"
        let path = basePath.isEmpty ? name : basePath + "/" + name
        let normalized = path.split(separator: "/").filter { $0 != "." && $0 != ".." }.joined(separator: "/")

        // Avoid duplicates
        var finalPath = normalized
        var counter = 1
        while project.files.contains(where: { $0.path == finalPath }) {
            finalPath = basePath.isEmpty ? "untitled\(counter).txt" : basePath + "/untitled\(counter).txt"
            counter += 1
        }

        let file = ProjectFile(path: finalPath, content: "", project: project)
        modelContext.insert(file)
        project.updatedAt = Date()

        do {
            try modelContext.save()
            openFilePaths.append(finalPath)
            selectedFilePath = finalPath
        } catch {
            persistenceError = "Failed to create file."
        }
    }

    private func deleteFile(_ file: ProjectFile) {
        if file.isDirectory {
            let prefix = file.path + "/"
            let childCount = project.files.filter { $0.path.hasPrefix(prefix) }.count
            if childCount > 0 {
                persistenceError = "Directory not empty: \(file.path) (\(childCount) items). Delete contents first."
                return
            }
        }

        let path = file.path
        openFilePaths.removeAll { $0 == path }
        if selectedFilePath == path {
            selectedFilePath = openFilePaths.last
        }
        modelContext.delete(file)
        project.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete \(file.isDirectory ? "directory" : "file")."
        }
    }

    private func renameFile(_ file: ProjectFile, to newName: String) {
        let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedName.isEmpty else {
            persistenceError = "Name cannot be empty."
            return
        }
        guard !sanitizedName.contains("/") else {
            persistenceError = "Name cannot contain '/'."
            return
        }

        let oldPath = file.path
        let components = oldPath.split(separator: "/").dropLast()
        let parentPath = components.joined(separator: "/")
        let newPath = parentPath.isEmpty ? sanitizedName : parentPath + "/" + sanitizedName

        guard newPath != oldPath else { return }

        if project.files.contains(where: { $0.id != file.id && $0.path == newPath }) {
            persistenceError = "A file or folder named '\(sanitizedName)' already exists here."
            return
        }

        if file.isDirectory {
            let oldPrefix = oldPath + "/"
            let newPrefix = newPath + "/"

            for child in project.files where child.path.hasPrefix(oldPrefix) {
                let suffix = String(child.path.dropFirst(oldPrefix.count))
                let candidate = newPrefix + suffix
                let collides = project.files.contains { existing in
                    existing.id != child.id
                    && !existing.path.hasPrefix(oldPrefix)
                    && existing.path == candidate
                }
                if collides {
                    persistenceError = "Cannot rename folder because '\(candidate)' already exists."
                    return
                }
            }

            for child in project.files where child.path.hasPrefix(oldPrefix) {
                let suffix = String(child.path.dropFirst(oldPrefix.count))
                child.path = newPrefix + suffix
                child.updatedAt = Date()
            }

            openFilePaths = openFilePaths.map { path in
                guard path.hasPrefix(oldPrefix) else { return path }
                let suffix = String(path.dropFirst(oldPrefix.count))
                return newPrefix + suffix
            }
            if let selectedPath = selectedFilePath, selectedPath.hasPrefix(oldPrefix) {
                let suffix = String(selectedPath.dropFirst(oldPrefix.count))
                selectedFilePath = newPrefix + suffix
            }
        }

        file.path = newPath
        file.updatedAt = Date()
        project.updatedAt = Date()

        if !file.isDirectory {
            if let index = openFilePaths.firstIndex(of: oldPath) {
                openFilePaths[index] = newPath
            }
            if selectedFilePath == oldPath {
                selectedFilePath = newPath
            }
        }

        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to rename item."
        }
    }

    private func reconcileOpenTabs() {
        let validPaths = Set(project.files.filter { !$0.isDirectory }.map(\.path))
        let stale = openFilePaths.filter { !validPaths.contains($0) }
        guard !stale.isEmpty else { return }
        openFilePaths.removeAll { !validPaths.contains($0) }
        if let sel = selectedFilePath, !validPaths.contains(sel) {
            selectedFilePath = openFilePaths.last
        }
    }

    private func saveBlockToFile(_ block: ExtractedCodeBlock) {
        let ext = CodeLanguage.extensionForLanguage(block.language)
        var finalPath = "untitled.\(ext)"
        var counter = 1
        while project.files.contains(where: { $0.path == finalPath }) {
            finalPath = "untitled\(counter).\(ext)"
            counter += 1
        }

        let file = ProjectFile(path: finalPath, content: block.code, project: project)
        modelContext.insert(file)
        project.updatedAt = Date()

        do {
            try modelContext.save()
            openFilePaths.append(finalPath)
            selectedFilePath = finalPath
        } catch {
            persistenceError = "Failed to save code block as file."
        }
    }

    private func loadProjectConversation() {
        let convID = project.conversationID
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convID })
        projectConversation = try? modelContext.fetch(descriptor).first
    }

    private func exportProject() {
        do {
            let url = try ProjectExporter.exportAsZip(project: project)
            #if os(macOS)
            exportWithSavePanel(url: url)
            #else
            exportURL = url
            showExportSheet = true
            #endif
        } catch {
            persistenceError = "Export failed: \(error.localizedDescription)"
        }
    }

    #if os(macOS)
    private func exportWithSavePanel(url: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(project.name).zip"
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                self.persistenceError = "Failed to save zip: \(error.localizedDescription)"
            }
        }
    }
    #endif
}

// MARK: - Resizable Panel Divider

private struct PanelDivider: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    @State private var isHovered = false

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                ZStack {
                    Color.surface.frame(height: 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isHovered ? Color.accent : Color.textTertiary)
                        .frame(width: 36, height: 3)
                }
                .frame(height: 7)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                #if os(macOS)
                .onHover { isHovered = $0 }
                .cursor(isHovered, .resizeUpDown)
                #endif
            case .vertical:
                ZStack {
                    Color.surface.frame(width: 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isHovered ? Color.accent : Color.textTertiary)
                        .frame(width: 3, height: 36)
                }
                .frame(width: 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                #if os(macOS)
                .onHover { isHovered = $0 }
                .cursor(isHovered, .resizeLeftRight)
                #endif
            }
        }
        .background(Color.bgSecondary)
    }
}

#if os(macOS)
private extension View {
    func cursor(_ active: Bool, _ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering && active {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#endif

// MARK: - iOS Share Sheet

#if os(iOS)
struct ShareSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
