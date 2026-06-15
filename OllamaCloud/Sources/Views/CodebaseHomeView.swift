import SwiftUI

/// The Codebases tab: a list of code workspaces (file tree + editor + agentic
/// Builder/Reviewer chat). Reuses `ProjectListView` for the list (relabeled) and
/// `CodeWorkspaceView` for the workspace, but creation goes through a dedicated
/// "New Codebase" sheet (name + Builder/Reviewer models + rounds) to match the
/// manticthink website rather than the bare model picker.
struct CodebaseHomeView: View {
    private let accountScopeKey = AccountScope.currentKey()
    @State private var selection: Project?
    @State private var createToken = 0
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ProjectListView(
                selection: $selection,
                createToken: $createToken,
                title: "Codebases",
                newButtonTitle: "+ NEW CODEBASE",
                emptyTitle: "No Codebases",
                onCreate: { showCreate = true }
            )
            .navigationDestination(item: $selection) { project in
                CodeWorkspaceView(project: project)
            }
            .sheet(isPresented: $showCreate) {
                CodebaseCreateView(accountScopeKey: accountScopeKey) { project in
                    selection = project
                }
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
            }
        }
    }
}
