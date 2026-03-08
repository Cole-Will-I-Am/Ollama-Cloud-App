import SwiftUI

// MARK: - Flattened row for rendering

private struct TreeRow: Identifiable {
    let id: String
    let node: FileNode
    let depth: Int
    let isLast: Bool
    let ancestorIsLast: [Bool]
}

struct FileTreeView: View {
    let files: [ProjectFile]
    @Binding var selectedPath: String?
    let onDelete: (ProjectFile) -> Void
    let onRename: (ProjectFile, String) -> Void
    let onNewFile: (String) -> Void
    @State private var filePendingRename: ProjectFile?
    @State private var renameText = ""
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        let nodes = FileNode.buildTree(from: files)
        let rows = flattenNodes(nodes, depth: 0, ancestorIsLast: [])

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    rowView(row: row)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { expandAllDirectories(in: FileNode.buildTree(from: files)) }
        .alert("Rename", isPresented: Binding(
            get: { filePendingRename != nil },
            set: { if !$0 { filePendingRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                guard let filePendingRename else { return }
                onRename(filePendingRename, renameText)
                self.filePendingRename = nil
            }
            Button("Cancel", role: .cancel) {
                filePendingRename = nil
            }
        } message: {
            Text("Enter a new name.")
        }
    }

    // MARK: - Flatten tree into rows

    private func flattenNodes(_ nodes: [FileNode], depth: Int, ancestorIsLast: [Bool]) -> [TreeRow] {
        var rows: [TreeRow] = []
        for (index, node) in nodes.enumerated() {
            let isLast = index == nodes.count - 1
            rows.append(TreeRow(id: node.id, node: node, depth: depth, isLast: isLast, ancestorIsLast: ancestorIsLast))
            if node.isDirectory && expandedPaths.contains(node.id) {
                rows += flattenNodes(node.sortedChildren, depth: depth + 1, ancestorIsLast: ancestorIsLast + [isLast])
            }
        }
        return rows
    }

    // MARK: - Single row

    @ViewBuilder
    private func rowView(row: TreeRow) -> some View {
        let node = row.node
        let isSelected = selectedPath == node.id

        Button {
            if node.isDirectory {
                withAnimation(.snappy(duration: 0.2)) {
                    if expandedPaths.contains(node.id) {
                        expandedPaths.remove(node.id)
                    } else {
                        expandedPaths.insert(node.id)
                    }
                }
            } else {
                selectedPath = node.id
            }
        } label: {
            HStack(spacing: 0) {
                // Ancestor continuation lines
                ForEach(0..<row.ancestorIsLast.count, id: \.self) { i in
                    ZStack {
                        if !row.ancestorIsLast[i] {
                            Rectangle()
                                .fill(Color.textTertiary)
                                .frame(width: 0.5)
                        }
                    }
                    .frame(width: 18, height: 24)
                }

                // Connector column (tee or elbow) — only for non-root
                if row.depth > 0 {
                    connectorView(isLast: row.isLast)
                        .frame(width: 18, height: 24)
                }

                Spacer().frame(width: 6)

                // Chevron for directories
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(expandedPaths.contains(node.id) ? 90 : 0))
                        .frame(width: 12)
                        .padding(.trailing, 4)
                }

                // File name
                Text(node.name)
                    .font(.app(13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.accent : Color.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentSoft.opacity(0.5)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let file = node.file {
                Button("Rename") {
                    filePendingRename = file
                    renameText = node.name
                }
                Button("Delete") { onDelete(file) }
            }
            if node.isDirectory {
                Button("New File Here") { onNewFile(node.id) }
            }
        }
    }

    // MARK: - Connector shapes

    @ViewBuilder
    private func connectorView(isLast: Bool) -> some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let midX = geo.size.width / 2

            // Vertical line: full height for tee (├), top half for elbow (└)
            Rectangle()
                .fill(Color.textTertiary)
                .frame(width: 0.5, height: isLast ? midY : geo.size.height)
                .position(x: midX, y: isLast ? midY / 2 : midY)

            // Horizontal branch from center to right edge
            Rectangle()
                .fill(Color.textTertiary)
                .frame(width: geo.size.width / 2, height: 0.5)
                .position(x: midX + geo.size.width / 4, y: midY)
        }
    }

    // MARK: - Auto-expand

    private func expandAllDirectories(in nodes: [FileNode]) {
        for node in nodes {
            if node.isDirectory {
                expandedPaths.insert(node.id)
                expandAllDirectories(in: node.children)
            }
        }
    }
}

// MARK: - Tree Node

struct FileNode: Identifiable {
    let id: String        // full path
    let name: String
    let isDirectory: Bool
    var children: [FileNode]
    let file: ProjectFile?

    var fileExtension: String {
        guard let dotIndex = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dotIndex)...]).lowercased()
    }

    var sortedChildren: [FileNode] {
        children.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func buildTree(from files: [ProjectFile]) -> [FileNode] {
        var root: [String: FileNode] = [:]

        for file in files.sorted(by: { $0.path < $1.path }) {
            let parts = file.path.split(separator: "/").map(String.init)
            insertInto(root: &root, parts: parts, fullPath: "", file: file, partIndex: 0)
        }

        return sortNodes(Array(root.values))
    }

    private static func insertInto(
        root: inout [String: FileNode],
        parts: [String],
        fullPath: String,
        file: ProjectFile,
        partIndex: Int
    ) {
        guard partIndex < parts.count else { return }
        let part = parts[partIndex]
        let currentPath = fullPath.isEmpty ? part : fullPath + "/" + part
        let isLast = partIndex == parts.count - 1

        if root[part] == nil {
            root[part] = FileNode(
                id: currentPath,
                name: part,
                isDirectory: isLast ? file.isDirectory : true,
                children: [],
                file: isLast ? file : nil
            )
        }

        if !isLast {
            var node = root[part]!
            var childMap = Dictionary(uniqueKeysWithValues: node.children.map { ($0.name, $0) })
            insertInto(root: &childMap, parts: parts, fullPath: currentPath, file: file, partIndex: partIndex + 1)
            node.children = Array(childMap.values)
            root[part] = node
        }
    }

    private static func sortNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.map { node in
            var sorted = node
            sorted.children = sortNodes(node.children)
            return sorted
        }
    }
}
