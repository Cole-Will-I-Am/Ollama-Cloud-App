import SwiftUI

/// The Codebases tab: a list of code workspaces (file tree + editor + agentic
/// Builder/Reviewer chat). Reuses the existing `ProjectListView` (relabeled) and
/// `CodeWorkspaceView`, which back the website's "Codebases" concept.
struct CodebaseHomeView: View {
    @State private var selection: Project?
    @State private var createToken = 0

    var body: some View {
        NavigationStack {
            ProjectListView(
                selection: $selection,
                createToken: $createToken,
                title: "Codebases",
                newButtonTitle: "+ NEW CODEBASE",
                emptyTitle: "No Codebases"
            )
            .navigationDestination(item: $selection) { project in
                CodeWorkspaceView(project: project)
            }
        }
    }
}
