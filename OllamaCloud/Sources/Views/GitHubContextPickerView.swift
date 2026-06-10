import SwiftUI

struct GitHubContextPickerView: View {
    let onAttach: ([GitHubContextFile]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GitHubContextPickerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                content
            }
            .navigationTitle("GitHub")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE") { dismiss() }
                        .font(.appLabel(11))
                        .tracking(2)
                        .foregroundStyle(Color.textSecondary)
                }
                if model.isConnected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("DISCONNECT") {
                            model.disconnect()
                        }
                        .font(.appLabel(10))
                        .tracking(1.6)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.openedRepository != nil {
                    attachBar
                }
            }
            .task {
                await model.start()
            }
            .alert("GitHub", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isCheckingToken {
            ProgressView()
                .tint(Color.accent)
        } else if !model.isConnected {
            tokenGate
        } else if model.openedRepository != nil {
            repositoryBrowser
        } else {
            repositoryList
        }
    }

    private var tokenGate: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.accent)

            VStack(spacing: 8) {
                Text("Connect GitHub")
                    .font(.app(20, weight: .light))
                    .foregroundStyle(Color.textPrimary)
                Text("Paste a fine-grained token with read-only Contents access for the repositories you want to attach.")
                    .font(.app(13))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }

            VStack(spacing: 10) {
                SecureField("GitHub token", text: $model.tokenInput)
                    .font(.appMono(13))
                    #if os(iOS)
                    .textContentType(.password)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.borderLight, lineWidth: 0.5))
                    )

                Button {
                    Task { await model.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(model.isConnecting ? "CONNECTING" : "CONNECT")
                            .font(.appLabel(11))
                            .tracking(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(model.canConnect ? AnyShapeStyle(LinearGradient.accentGradient) : AnyShapeStyle(Color.bgTertiary))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!model.canConnect || model.isConnecting)

                if let error = model.inlineError {
                    Text(error)
                        .font(.app(12))
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)

            Link("Create a GitHub token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                .font(.appLabel(10))
                .tracking(1.8)
                .foregroundStyle(Color.accent)

            Spacer(minLength: 12)
        }
        .padding(24)
        .frame(maxWidth: 520)
    }

    private var repositoryList: some View {
        VStack(spacing: 12) {
            accountHeader

            HStack(spacing: 8) {
                TextField("Search repos or owner/repo", text: $model.repoSearch)
                    .font(.app(14))
                    #if os(iOS)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.borderLight, lineWidth: 0.5))
                    )

                Button {
                    Task { await model.openRepositoryFromSearch() }
                } label: {
                    Text("OPEN")
                        .font(.appLabel(10))
                        .tracking(1.6)
                        .foregroundStyle(model.canOpenManualRepository ? Color.accent : Color.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(model.canOpenManualRepository ? Color.accentSoft : Color.surface))
                        .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(!model.canOpenManualRepository || model.isOpeningRepository)
            }
            .padding(.horizontal, 16)

            if let error = model.inlineError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11, weight: .ultraLight))
                    Text(error)
                        .font(.app(12))
                        .lineLimit(3)
                    Spacer()
                }
                .foregroundStyle(Color.danger)
                .padding(.horizontal, 16)
            }

            if model.isLoadingRepos {
                Spacer()
                ProgressView()
                    .tint(Color.accent)
                Spacer()
            } else if model.filteredRepositories.isEmpty {
                emptyState(icon: "folder.badge.questionmark", title: "No repos found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.filteredRepositories) { repo in
                            repositoryRow(repo)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var repositoryBrowser: some View {
        VStack(spacing: 12) {
            repositoryHeader

            HStack(spacing: 8) {
                TextField("Filter files", text: $model.fileSearch)
                    .font(.app(14))
                    #if os(iOS)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.borderLight, lineWidth: 0.5))
                    )

                Menu {
                    ForEach(model.branches) { branch in
                        Button(branch.name) {
                            Task { await model.selectBranch(branch.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 11, weight: .ultraLight))
                        Text(model.selectedBranchName.isEmpty ? "BRANCH" : model.selectedBranchName)
                            .font(.appLabel(9))
                            .tracking(1.2)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.accentSoft))
                    .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                    .frame(maxWidth: 170)
                }
                .disabled(model.branches.isEmpty || model.isLoadingTree)
            }
            .padding(.horizontal, 16)

            if model.treeWasTruncated {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .ultraLight))
                    Text("Large repo. GitHub truncated the file list; use the filter to narrow results.")
                        .font(.app(11))
                        .lineLimit(2)
                    Spacer()
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
            }

            if model.isLoadingTree || model.isOpeningRepository {
                Spacer()
                ProgressView()
                    .tint(Color.accent)
                Spacer()
            } else if model.filteredFiles.isEmpty {
                emptyState(icon: "doc.text.magnifyingglass", title: "No text files found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.filteredFiles) { file in
                            fileRow(file)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                }
            }
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 13, weight: .ultraLight))
                .foregroundStyle(Color.success)
            Text(model.login.map { "Connected as @\($0)" } ?? "Connected")
                .font(.app(12))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button {
                Task { await model.loadRepositories() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .ultraLight))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingRepos)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var repositoryHeader: some View {
        HStack(spacing: 10) {
            Button {
                model.closeRepository()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.surface))
                    .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.openedRepository?.fullName ?? "Repository")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(model.tree.count) text files")
                    .font(.app(11))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var attachBar: some View {
        HStack(spacing: 12) {
            Text("\(model.selectedCount) selected")
                .font(.appLabel(10))
                .tracking(1.6)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button {
                Task {
                    let files = await model.fetchSelectedFiles()
                    guard !files.isEmpty else { return }
                    onAttach(files)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isAttaching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(model.isAttaching ? "FETCHING" : "ATTACH TO CHAT")
                        .font(.appLabel(10))
                        .tracking(1.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(model.selectedCount == 0 ? AnyShapeStyle(Color.bgTertiary) : AnyShapeStyle(LinearGradient.accentGradient))
                )
            }
            .buttonStyle(.plain)
            .disabled(model.selectedCount == 0 || model.isAttaching)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgPrimary.opacity(0.94))
        .overlay(Rectangle().fill(Color.border).frame(height: 0.5), alignment: .top)
    }

    private func repositoryRow(_ repo: GitHubRepository) -> some View {
        Button {
            Task { await model.openRepository(repo) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: repo.isPrivate ? "lock" : "folder")
                    .font(.system(size: 13, weight: .ultraLight))
                    .foregroundStyle(Color.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.fullName)
                        .font(.app(14))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(repo.defaultBranch)
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if repo.isPrivate {
                    Text("PRIVATE")
                        .font(.appLabel(8))
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.surface))
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ file: GitHubTreeItem) -> some View {
        let selected = model.isSelected(file)
        return Button {
            model.toggleSelection(file)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accent : Color.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .font(.app(13))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size ?? 0), countStyle: .file))
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentSoft : Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Color.accent.opacity(0.22) : Color.border, lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Color.textTertiary)
            Text(title)
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(24)
    }
}

@MainActor
private final class GitHubContextPickerViewModel: ObservableObject {
    @Published var tokenInput = ""
    @Published var repoSearch = ""
    @Published var fileSearch = ""
    @Published var alertMessage: String?

    @Published private(set) var isCheckingToken = true
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isLoadingRepos = false
    @Published private(set) var isOpeningRepository = false
    @Published private(set) var isLoadingTree = false
    @Published private(set) var isAttaching = false
    @Published private(set) var inlineError: String?
    @Published private(set) var login: String?
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var openedRepository: GitHubRepository?
    @Published private(set) var branches: [GitHubBranch] = []
    @Published private(set) var selectedBranchName = ""
    @Published private(set) var tree: [GitHubTreeItem] = []
    @Published private(set) var treeWasTruncated = false
    @Published private(set) var selectedPaths: Set<String> = []

    private let api = GitHubAPIClient()
    private var token = ""
    private var didStart = false

    private static let tokenKey = "github_context_token"
    private static let fileCharacterCap = 200_000
    private static let maxSelectedFiles = 40

    var canConnect: Bool {
        !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canOpenManualRepository: Bool {
        parseManualRepository(repoSearch) != nil
    }

    var selectedCount: Int {
        selectedPaths.count
    }

    var filteredRepositories: [GitHubRepository] {
        let query = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = repositories.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        guard !query.isEmpty, parseManualRepository(query) == nil else { return source }
        return source.filter { repo in
            repo.fullName.lowercased().contains(query)
                || repo.name.lowercased().contains(query)
        }
    }

    var filteredFiles: [GitHubTreeItem] {
        let query = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = tree.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        guard !query.isEmpty else { return source }
        return source.filter { $0.path.lowercased().contains(query) }
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        if let savedToken = KeychainHelper.load(key: Self.tokenKey),
           !savedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await connect(using: savedToken, persist: false)
        } else {
            isCheckingToken = false
        }
    }

    func connect() async {
        await connect(using: tokenInput, persist: true)
    }

    func disconnect() {
        KeychainHelper.delete(key: Self.tokenKey)
        token = ""
        tokenInput = ""
        login = nil
        isConnected = false
        repositories = []
        closeRepository()
    }

    func loadRepositories() async {
        guard !token.isEmpty else { return }
        isLoadingRepos = true
        inlineError = nil
        defer { isLoadingRepos = false }

        do {
            repositories = try await api.fetchRepositories(token: token)
        } catch {
            inlineError = displayMessage(for: error)
        }
    }

    func openRepositoryFromSearch() async {
        guard let target = parseManualRepository(repoSearch) else { return }
        isOpeningRepository = true
        inlineError = nil
        defer { isOpeningRepository = false }

        do {
            let repo = try await api.fetchRepository(owner: target.owner, name: target.name, token: token)
            await openRepository(repo)
        } catch {
            alertMessage = displayMessage(for: error)
        }
    }

    func openRepository(_ repository: GitHubRepository) async {
        openedRepository = repository
        selectedPaths.removeAll()
        tree = []
        treeWasTruncated = false
        branches = []
        selectedBranchName = ""
        isOpeningRepository = true
        defer { isOpeningRepository = false }

        do {
            let loadedBranches = try await api.fetchBranches(repository: repository, token: token)
            branches = loadedBranches.isEmpty
                ? [GitHubBranch(name: repository.defaultBranch, sha: repository.defaultBranch)]
                : loadedBranches
            let defaultBranch = branches.first { $0.name == repository.defaultBranch } ?? branches.first
            selectedBranchName = defaultBranch?.name ?? repository.defaultBranch
            await loadTree(branchName: selectedBranchName)
        } catch {
            closeRepository()
            alertMessage = displayMessage(for: error)
        }
    }

    func closeRepository() {
        openedRepository = nil
        branches = []
        selectedBranchName = ""
        tree = []
        treeWasTruncated = false
        selectedPaths.removeAll()
        fileSearch = ""
    }

    func selectBranch(_ name: String) async {
        guard name != selectedBranchName else { return }
        selectedBranchName = name
        selectedPaths.removeAll()
        await loadTree(branchName: name)
    }

    func toggleSelection(_ file: GitHubTreeItem) {
        if selectedPaths.contains(file.path) {
            selectedPaths.remove(file.path)
            return
        }
        guard selectedPaths.count < Self.maxSelectedFiles else {
            alertMessage = "Select \(Self.maxSelectedFiles) files or fewer."
            return
        }
        selectedPaths.insert(file.path)
    }

    func isSelected(_ file: GitHubTreeItem) -> Bool {
        selectedPaths.contains(file.path)
    }

    func fetchSelectedFiles() async -> [GitHubContextFile] {
        guard let repository = openedRepository, !selectedPaths.isEmpty else { return [] }
        if selectedPaths.count > Self.maxSelectedFiles {
            alertMessage = "Select \(Self.maxSelectedFiles) files or fewer."
            return []
        }

        isAttaching = true
        defer { isAttaching = false }

        let byPath = Dictionary(uniqueKeysWithValues: tree.map { ($0.path, $0) })
        var files: [GitHubContextFile] = []
        var failed = 0

        for path in selectedPaths.sorted() {
            guard let item = byPath[path] else { continue }

            do {
                var content = try await api.fetchBlobText(repository: repository, sha: item.sha, token: token)
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let originalCount = content.count
                if originalCount > Self.fileCharacterCap {
                    content = String(content.prefix(Self.fileCharacterCap))
                        + "\n\n[Truncated to \(Self.fileCharacterCap) characters]"
                }

                files.append(
                    GitHubContextFile(
                        name: "\(repository.fullName):\(path)",
                        content: content,
                        originalCharacterCount: originalCount
                    )
                )
            } catch {
                failed += 1
            }
        }

        if files.isEmpty {
            alertMessage = failed > 0
                ? "Could not fetch the selected GitHub files."
                : "No selected GitHub files contained readable text."
        } else if failed > 0 {
            alertMessage = "Attached \(files.count) file(s). \(failed) file(s) could not be fetched."
        }

        return files
    }

    private func connect(using rawToken: String, persist: Bool) async {
        let candidate = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            inlineError = GitHubAPIError.missingToken.errorDescription
            isCheckingToken = false
            return
        }

        isConnecting = true
        isCheckingToken = true
        inlineError = nil
        defer {
            isConnecting = false
            isCheckingToken = false
        }

        do {
            let account = try await api.fetchCurrentUser(token: candidate)
            token = candidate
            login = account.login
            isConnected = true
            tokenInput = ""
            if persist {
                _ = KeychainHelper.save(key: Self.tokenKey, value: candidate)
            }
            await loadRepositories()
        } catch {
            if !persist {
                KeychainHelper.delete(key: Self.tokenKey)
            }
            token = ""
            isConnected = false
            inlineError = displayMessage(for: error)
        }
    }

    private func loadTree(branchName: String) async {
        guard let repository = openedRepository, !branchName.isEmpty else { return }
        isLoadingTree = true
        treeWasTruncated = false
        defer { isLoadingTree = false }

        do {
            let response = try await api.fetchTree(repository: repository, ref: branchName, token: token)
            tree = response.tree
                .filter { $0.type == "blob" && GitHubAPIClient.isTextPath($0.path) }
            treeWasTruncated = response.truncated
        } catch {
            tree = []
            alertMessage = displayMessage(for: error)
        }
    }

    private func parseManualRepository(_ value: String) -> (owner: String, name: String)? {
        let pieces = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard pieces.count == 2,
              pieces.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        return (pieces[0], pieces[1])
    }

    private func displayMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }
}
