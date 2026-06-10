import Foundation

struct GitHubAccount: Decodable, Equatable {
    let login: String
}

struct GitHubRepository: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let owner: String
    let isPrivate: Bool
    let defaultBranch: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
        case defaultBranch = "default_branch"
    }

    private struct Owner: Decodable, Hashable {
        let login: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fullName = try container.decode(String.self, forKey: .fullName)
        owner = try container.decode(Owner.self, forKey: .owner).login
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        defaultBranch = try container.decode(String.self, forKey: .defaultBranch)
    }
}

struct GitHubBranch: Decodable, Identifiable, Hashable {
    let name: String
    private let commit: Commit

    var id: String { name }
    var sha: String { commit.sha }

    private struct Commit: Decodable, Hashable {
        let sha: String
    }

    init(name: String, sha: String) {
        self.name = name
        self.commit = Commit(sha: sha)
    }
}

struct GitHubTreeItem: Decodable, Identifiable, Hashable {
    let path: String
    let type: String
    let sha: String
    let size: Int?

    var id: String { path }
}

struct GitHubTreeResponse: Decodable, Equatable {
    let tree: [GitHubTreeItem]
    let truncated: Bool
}

struct GitHubContextFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let content: String
    let originalCharacterCount: Int
}

enum GitHubAPIError: LocalizedError, Equatable {
    case missingToken
    case unauthorized
    case notFound
    case rateLimited
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Enter a GitHub token."
        case .unauthorized:
            return "GitHub rejected that token."
        case .notFound:
            return "Repository not found or token has no access."
        case .rateLimited:
            return "GitHub rate limit reached. Try again later."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}

actor GitHubAPIClient {
    private let baseHost = "api.github.com"
    private let session: URLSession
    private static let pathSegmentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrentUser(token: String) async throws -> GitHubAccount {
        try await request(path: "/user", token: token)
    }

    func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        try await request(
            path: "/user/repos",
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member")
            ],
            token: token
        )
    }

    func fetchRepository(owner: String, name: String, token: String) async throws -> GitHubRepository {
        try await request(
            path: "/repos/\(Self.pathSegment(owner))/\(Self.pathSegment(name))",
            token: token
        )
    }

    func fetchBranches(repository: GitHubRepository, token: String) async throws -> [GitHubBranch] {
        try await request(
            path: "/repos/\(Self.pathSegment(repository.owner))/\(Self.pathSegment(repository.name))/branches",
            queryItems: [URLQueryItem(name: "per_page", value: "100")],
            token: token
        )
    }

    func fetchTree(repository: GitHubRepository, ref: String, token: String) async throws -> GitHubTreeResponse {
        try await request(
            path: "/repos/\(Self.pathSegment(repository.owner))/\(Self.pathSegment(repository.name))/git/trees/\(Self.pathSegment(ref))",
            queryItems: [URLQueryItem(name: "recursive", value: "1")],
            token: token
        )
    }

    func fetchBlobText(repository: GitHubRepository, sha: String, token: String) async throws -> String {
        let blob: GitHubBlob = try await request(
            path: "/repos/\(Self.pathSegment(repository.owner))/\(Self.pathSegment(repository.name))/git/blobs/\(Self.pathSegment(sha))",
            token: token
        )

        guard blob.encoding.lowercased() == "base64" else {
            throw GitHubAPIError.invalidResponse
        }

        let normalized = blob.content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(normalized)) else {
            throw GitHubAPIError.invalidResponse
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw GitHubAPIError.invalidResponse
    }

    static func isTextPath(_ path: String) -> Bool {
        let base = path.split(separator: "/").last.map(String.init) ?? path
        let lowerBase = base.lowercased()
        if exactTextFilenames.contains(lowerBase) {
            return true
        }
        let ext = (base as NSString).pathExtension.lowercased()
        return textExtensions.contains(ext)
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String
    ) async throws -> T {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw GitHubAPIError.missingToken }

        guard let url = makeURL(path: path, queryItems: queryItems) else {
            throw GitHubAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                throw mapHTTPError(statusCode: http.statusCode, data: data)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as GitHubAPIError {
            throw error
        } catch is DecodingError {
            throw GitHubAPIError.invalidResponse
        } catch {
            throw GitHubAPIError.requestFailed(error.localizedDescription)
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = baseHost
        components.percentEncodedPath = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> GitHubAPIError {
        switch statusCode {
        case 401, 403:
            if statusCode == 403,
               let message = message(from: data),
               message.localizedCaseInsensitiveContains("rate limit") {
                return .rateLimited
            }
            return .unauthorized
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        default:
            if let message = message(from: data), !message.isEmpty {
                return .requestFailed("GitHub \(statusCode): \(message)")
            }
            return .requestFailed("GitHub request failed (\(statusCode)).")
        }
    }

    private func message(from data: Data) -> String? {
        try? JSONDecoder().decode(GitHubErrorResponse.self, from: data).message
    }

    private static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml",
        "xml", "html", "htm", "css", "js", "mjs", "ts", "tsx", "jsx",
        "py", "rb", "go", "rs", "java", "c", "h", "cpp", "cc", "cs",
        "php", "sh", "bash", "sql", "toml", "ini", "cfg", "log",
        "swift", "kt", "kts", "dart", "vue", "svelte", "graphql", "gql"
    ]

    private static let exactTextFilenames: Set<String> = [
        "dockerfile", "makefile", "license", "readme", "procfile",
        ".gitignore", ".env.example", ".npmrc", ".editorconfig",
        "gemfile", "rakefile", "podfile", "cartfile"
    ]
}

private struct GitHubBlob: Decodable {
    let content: String
    let encoding: String
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}
