import AppKit
import Foundation
import Observation

public struct GitHubPRItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let repo: String
    public let author: String
    public let isDraft: Bool
    public let url: URL

    public init(
        id: String,
        number: Int,
        title: String,
        repo: String,
        author: String,
        isDraft: Bool,
        url: URL
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repo = repo
        self.author = author
        self.isDraft = isDraft
        self.url = url
    }
}

public struct JiraIssueItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let key: String
    public let summary: String
    public let status: String
    public let priority: String
    public let url: URL

    public init(id: String, key: String, summary: String, status: String, priority: String, url: URL) {
        self.id = id
        self.key = key
        self.summary = summary
        self.status = status
        self.priority = priority
        self.url = url
    }
}

public struct LocalAIAgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let cpuPercent: Double
    public let isBusy: Bool

    public init(id: String, name: String, kind: String, cpuPercent: Double, isBusy: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.cpuPercent = cpuPercent
        self.isBusy = isBusy
    }
}

@MainActor
@Observable
public final class DeveloperHubService {
    public private(set) var githubPRs: [GitHubPRItem] = []
    public private(set) var githubError: String?
    public private(set) var isLoadingGitHub: Bool = false

    public private(set) var jiraIssues: [JiraIssueItem] = []
    public private(set) var jiraError: String?
    public private(set) var isLoadingJira: Bool = false

    public private(set) var aiSessions: [LocalAIAgentSession] = []

    public var translationInput: String = ""
    public var translationOutput: String = ""
    public var translationTargetLanguage: String = "English"
    public private(set) var isTranslating: Bool = false
    public private(set) var translationError: String?

    public init() {}

    public func refreshAll(settings: AppSettings) {
        refreshAISessions()
        Task { [weak self] in
            guard let self else { return }
            await self.refreshGitHub(token: settings.githubToken, reposCSV: settings.githubRepos)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshJira(
                baseURL: settings.jiraBaseURL,
                email: settings.jiraEmail,
                token: settings.jiraToken,
                jql: settings.jiraJQL
            )
        }
    }

    public func refreshAISessions() {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        Task.detached(priority: .utility) {
            let detected = Self.sampleLocalAgentProcesses(runningBundleIDs: runningBundleIDs)
            await MainActor.run { [weak self] in
                self?.aiSessions = detected
            }
        }
    }

    public func refreshGitHub(token: String, reposCSV: String) async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let repos = reposCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("/") }

        guard !repos.isEmpty || !trimmedToken.isEmpty else {
            githubPRs = []
            githubError = nil
            return
        }

        isLoadingGitHub = true
        githubError = nil
        defer { isLoadingGitHub = false }

        do {
            let items = try await Task.detached(priority: .utility) {
                try await Self.fetchGitHubPRs(token: trimmedToken, repos: repos)
            }.value
            githubPRs = items
        } catch {
            githubError = error.localizedDescription
        }
    }

    public func refreshJira(baseURL: String, email: String, token: String, jql: String) async {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBase.isEmpty, !cleanEmail.isEmpty, !cleanToken.isEmpty else {
            jiraIssues = []
            jiraError = nil
            return
        }

        isLoadingJira = true
        jiraError = nil
        defer { isLoadingJira = false }

        do {
            let items = try await Task.detached(priority: .utility) {
                try await Self.fetchJiraIssues(baseURL: cleanBase, email: cleanEmail, token: cleanToken, jql: jql)
            }.value
            jiraIssues = items
        } catch {
            jiraError = error.localizedDescription
        }
    }

    public func translate(settings: AppSettings) async {
        let source = translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        isTranslating = true
        translationError = nil
        defer { isTranslating = false }

        let targetLang = translationTargetLanguage
        let provider = settings.translatorProvider
        let endpoint = settings.translatorEndpoint
        let model = settings.translatorModel
        let apiKey = settings.openAIKey

        do {
            let translated = try await Task.detached(priority: .userInitiated) {
                try await Self.performTranslation(
                    text: source,
                    targetLanguage: targetLang,
                    provider: provider,
                    endpoint: endpoint,
                    model: model,
                    apiKey: apiKey
                )
            }.value
            translationOutput = translated
        } catch {
            translationError = error.localizedDescription
        }
    }

    private nonisolated static func sampleLocalAgentProcesses(runningBundleIDs: Set<String>) -> [LocalAIAgentSession] {
        var results: [LocalAIAgentSession] = []

        if runningBundleIDs.contains("com.todesktop.230313mzl4w4u92") {
            results.append(LocalAIAgentSession(id: "app-cursor", name: "Cursor IDE", kind: "IDE", cpuPercent: 0, isBusy: false))
        }
        if runningBundleIDs.contains("com.anthropic.claudefordesktop") {
            results.append(LocalAIAgentSession(id: "app-claude", name: "Claude Desktop", kind: "AI App", cpuPercent: 0, isBusy: false))
        }
        if runningBundleIDs.contains("dev.zed.zed") {
            results.append(LocalAIAgentSession(id: "app-zed", name: "Zed", kind: "IDE", cpuPercent: 0, isBusy: false))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let raw = String(data: data, encoding: .utf8) ?? ""
            for line in raw.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                guard parts.count == 3, let pid = Int(parts[0]) else { continue }
                let cpu = Double(parts[1]) ?? 0
                let cmd = String(parts[2])
                let lower = cmd.lowercased()
                let label: String?
                let kind: String
                if lower.hasSuffix("/claude") || lower == "claude" {
                    label = "Claude Code"
                    kind = "CLI Agent"
                } else if lower.contains("codex") {
                    label = "Codex CLI"
                    kind = "CLI Agent"
                } else if lower.hasSuffix("/ollama") || lower == "ollama" {
                    label = "Ollama Server"
                    kind = "Local LLM"
                } else if lower.contains("aider") {
                    label = "Aider"
                    kind = "CLI Agent"
                } else {
                    label = nil
                    kind = ""
                }

                if let label {
                    results.append(
                        LocalAIAgentSession(
                            id: "pid-\(pid)",
                            name: "\(label) (#\(pid))",
                            kind: kind,
                            cpuPercent: cpu,
                            isBusy: cpu >= 4.0
                        )
                    )
                }
            }
        } catch {
            // Best-effort process discovery only
        }

        return results
    }

    private nonisolated static func fetchGitHubPRs(token: String, repos: [String]) async throws -> [GitHubPRItem] {
        var collected: [GitHubPRItem] = []

        if repos.isEmpty {
            guard let url = URL(string: "https://api.github.com/search/issues?q=is:pr+is:open+involves:@me&per_page=10") else {
                return []
            }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "GitHub", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub HTTP \(http.statusCode)"])
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = root["items"] as? [[String: Any]] {
                for item in items {
                    guard let number = item["number"] as? Int,
                          let title = item["title"] as? String,
                          let htmlURLStr = item["html_url"] as? String,
                          let url = URL(string: htmlURLStr) else { continue }
                    let user = (item["user"] as? [String: Any])?["login"] as? String ?? ""
                    let repoURL = item["repository_url"] as? String ?? ""
                    let repoName = repoURL.split(separator: "/").suffix(2).joined(separator: "/")
                    let isDraft = item["draft"] as? Bool ?? false
                    collected.append(
                        GitHubPRItem(
                            id: "\(repoName)#\(number)",
                            number: number,
                            title: title,
                            repo: repoName.isEmpty ? "PR" : repoName,
                            author: user,
                            isDraft: isDraft,
                            url: url
                        )
                    )
                }
            }
            return collected
        }

        for repo in repos.prefix(5) {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/pulls?state=open&per_page=6") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "GitHub", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub \(repo) HTTP \(http.statusCode)"])
            }
            if let pulls = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for pr in pulls {
                    guard let number = pr["number"] as? Int,
                          let title = pr["title"] as? String,
                          let htmlURLStr = pr["html_url"] as? String,
                          let url = URL(string: htmlURLStr) else { continue }
                    let user = (pr["user"] as? [String: Any])?["login"] as? String ?? ""
                    let isDraft = pr["draft"] as? Bool ?? false
                    collected.append(
                        GitHubPRItem(
                            id: "\(repo)#\(number)",
                            number: number,
                            title: title,
                            repo: repo,
                            author: user,
                            isDraft: isDraft,
                            url: url
                        )
                    )
                }
            }
        }
        return collected
    }

    private nonisolated static func fetchJiraIssues(
        baseURL: String,
        email: String,
        token: String,
        jql: String
    ) async throws -> [JiraIssueItem] {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        components?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "fields", value: "summary,status,priority")
        ]
        guard let url = components?.url else {
            throw NSError(domain: "Jira", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Jira URL"])
        }
        let creds = Data("\(email):\(token)".utf8).base64EncodedString()
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "Jira", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Jira HTTP \(http.statusCode)"])
        }

        var items: [JiraIssueItem] = []
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issues = root["issues"] as? [[String: Any]] {
            for issue in issues {
                guard let key = issue["key"] as? String,
                      let fields = issue["fields"] as? [String: Any],
                      let summary = fields["summary"] as? String,
                      let browseURL = URL(string: "\(baseURL)/browse/\(key)") else { continue }
                let status = (fields["status"] as? [String: Any])?["name"] as? String ?? "Open"
                let priority = (fields["priority"] as? [String: Any])?["name"] as? String ?? "Normal"
                items.append(
                    JiraIssueItem(
                        id: key,
                        key: key,
                        summary: summary,
                        status: status,
                        priority: priority,
                        url: browseURL
                    )
                )
            }
        }
        return items
    }

    private nonisolated static func performTranslation(
        text: String,
        targetLanguage: String,
        provider: TranslatorProvider,
        endpoint: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        let prompt = "Translate the following text naturally into \(targetLanguage). Reply only with the translated text, preserving line breaks:\n\n\(text)"

        switch provider {
        case .ollama:
            let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(base.isEmpty ? "http://localhost:11434" : base)/api/generate") else {
                throw NSError(domain: "Translator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint URL"])
            }
            let payload: [String: Any] = [
                "model": model.isEmpty ? "llama3.2" : model,
                "prompt": prompt,
                "stream": false
            ]
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "Translator", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ollama HTTP \(http.statusCode)"])
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let reply = (obj?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if reply.isEmpty {
                throw NSError(domain: "Translator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty response from Ollama."])
            }
            return reply

        case .openAI:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw NSError(domain: "Translator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Add an OpenAI API key in Settings -> Dev & AI."])
            }
            guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                throw NSError(domain: "Translator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL"])
            }
            let payload: [String: Any] = [
                "model": model.isEmpty ? "gpt-4o-mini" : model,
                "messages": [
                    ["role": "system", "content": "You are a precise translator. Output only the translation."],
                    ["role": "user", "content": prompt]
                ]
            ]
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "Translator", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI HTTP \(http.statusCode)"])
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw NSError(domain: "Translator", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected OpenAI response format."])
        }
    }
}
