import Foundation

// MARK: - GitHub API Models

struct GitHubIssue: Codable {
    let title: String
    let body: String
    let labels: [String]
    let assignees: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case labels
        case assignees
    }
}

struct GitHubIssueResponse: Codable {
    let id: Int
    let number: Int
    let html_url: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case html_url
        case title
    }
}

// MARK: - GitHub Service

@MainActor
class GitHubService: ObservableObject {
    @Published var isExporting = false
    @Published var lastCreatedIssueURL: String?

    private let keychainService = KeychainService()
    private let owner = "lagaai"
    private let repo = "laga"

    func createIssue(from recording: Recording) async throws -> String {
        isExporting = true
        defer { isExporting = false }

        guard let token = keychainService.getGitHubToken() else {
            throw GitHubError.noToken
        }

        let issue = GitHubIssue(
            title: recording.displayTitle,
            body: formatIssueBody(recording),
            labels: ["idea", "transcription"],
            assignees: nil
        )

        // Create the GitHub API request
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(issue)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.networkError
        }

        switch httpResponse.statusCode {
        case 201:
            // Success - parse response
            let issueResponse = try JSONDecoder().decode(GitHubIssueResponse.self, from: data)
            lastCreatedIssueURL = issueResponse.html_url
            return issueResponse.html_url

        case 401:
            throw GitHubError.invalidToken

        case 403:
            throw GitHubError.insufficientPermissions

        case 404:
            throw GitHubError.repositoryNotFound

        case 422:
            throw GitHubError.validationError

        default:
            throw GitHubError.apiError(statusCode: httpResponse.statusCode)
        }
    }

    private func formatIssueBody(_ recording: Recording) -> String {
        var body = """

        ## 🎙️ Audio Recording

        **Created:** \(recording.createdAt.formatted(date: .long, time: .shortened))
        **Duration:** \(recording.formattedDuration)
        **File Size:** \(recording.formattedFileSize)

        """

        if let transcription = recording.transcription {
            body += """

            ## 📝 Transcription

            \(transcription.text)

            """

            if transcription.hasSummary {
                body += """
                ## 📋 Summary

                \(transcription.summary!)

                """
            }

            if transcription.hasTranslation {
                body += """
                ## 🌐 Translation

                \(transcription.translation!)

                """
            }

            body += """
            **Confidence:** \(transcription.formattedConfidence)
            **Processing Model:** \(transcription.modelUsed)
            **Processing Time:** \(transcription.formattedProcessingTime)

            """
        } else {
            body += """
            *No transcription available yet. Use the "Transcribe" button to generate AI transcription.*

            """
        }

        body += """

        ## 🔗 Technical Details

        - **Sample Rate:** \(recording.sampleRate) Hz
        - **Channels:** \(recording.channels)
        - **Format:** \(recording.format.uppercased())
        - **File:** `\(recording.fileName)`

        ---
        *Created with LAGA Ideas Recorder*
        """

        return body
    }

    func testConnection() async throws -> Bool {
        guard let token = keychainService.getGitHubToken() else {
            throw GitHubError.noToken
        }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }
}

// MARK: - Keychain Service for Secure Token Storage

class KeychainService {
    private let service = "ai.laga.ideas"
    private let account = "github_token"

    func saveGitHubToken(_ token: String) throws {
        let data = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing token if present
        SecItemDelete(query as CFDictionary)

        // Add new token
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    func getGitHubToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func deleteGitHubToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - GitHub Errors

enum GitHubError: LocalizedError {
    case noToken
    case invalidToken
    case insufficientPermissions
    case repositoryNotFound
    case validationError
    case networkError
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "GitHub Personal Access Token not found. Please configure it in Settings."
        case .invalidToken:
            return "Invalid GitHub token. Please check your token and try again."
        case .insufficientPermissions:
            return "Insufficient permissions. Token needs 'repo' scope for private repos or 'public_repo' for public repos."
        case .repositoryNotFound:
            return "Repository not found. Please check the repository exists and is accessible."
        case .validationError:
            return "Invalid issue data. Please check all required fields are filled."
        case .networkError:
            return "Network error. Please check your internet connection."
        case .apiError(let statusCode):
            return "GitHub API error (HTTP \(statusCode)). Please try again later."
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save token to Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete token from Keychain (status: \(status))"
        }
    }
}
