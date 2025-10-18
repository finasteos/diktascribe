import SwiftUI
import SPIndicator

// MARK: - GitHub Setup View

struct GitHubSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput: String = ""
    @State private var isValidating = false
    @State private var showTokenHelp = false
    @StateObject private var gitHubService = GitHubService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Connect to LAGA")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Configure your GitHub Personal Access Token to send recordings directly to the LAGA repository.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Token Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal Access Token")
                        .font(.headline)

                    SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $tokenInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .onSubmit {
                            validateAndSaveToken()
                        }

                    Text("Token needs 'repo' scope for private repositories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Help Section
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        showTokenHelp.toggle()
                    }) {
                        HStack {
                            Text("How to create a GitHub token")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: showTokenHelp ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }

                    if showTokenHelp {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Go to GitHub Settings → Developer settings → Personal access tokens")
                            Text("2. Click 'Generate new token (classic)'")
                            Text("3. Select scopes: 'repo' (full repository access)")
                            Text("4. Copy the generated token (you won't see it again!)")
                            Text("5. Paste it above and tap 'Save'")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        validateAndSaveToken()
                    }) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Save & Test Token")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tokenInput.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(tokenInput.isEmpty || isValidating)

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationTitle("GitHub Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func validateAndSaveToken() {
        guard !tokenInput.isEmpty else { return }

        isValidating = true

        Task {
            do {
                // Save token to Keychain
                try KeychainService().saveGitHubToken(tokenInput)

                // Test the connection
                let isValid = try await gitHubService.testConnection()

                if isValid {
                    SPIndicator.present(title: "Token Valid!", message: "Successfully connected to GitHub", preset: .done, haptic: .success)
                    dismiss()
                } else {
                    throw GitHubError.invalidToken
                }

            } catch {
                SPIndicator.present(title: "Token Invalid", message: error.localizedDescription, preset: .error, haptic: .error)

                // Clear invalid token
                try? KeychainService().deleteGitHubToken()
            }

            isValidating = false
        }
    }
}

// MARK: - Preview

struct GitHubSetupView_Previews: PreviewProvider {
    static var previews: some View {
        GitHubSetupView()
    }
}
