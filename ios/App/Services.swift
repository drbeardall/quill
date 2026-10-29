import CoreML
import Foundation
import Security
import WhisperKit

// MARK: - Keychain (Claude API key; only the app needs it)

enum Keychain {
    private static let service = "com.drbeardall.quill"
    private static let account = "anthropic_api_key"

    static var apiKey: String? {
        get {
            var q = base
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        set {
            SecItemDelete(base as CFDictionary)
            guard let v = newValue, !v.isEmpty else { return }
            var q = base
            q[kSecValueData as String] = Data(v.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

// MARK: - Claude

struct ClaudeClient {
    let apiKey: String
    let model: String

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func complete(system: String, user: String, maxTokens: Int = 2048) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            throw APIError(message: msg)
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dictation logic (port of Engine in core.py)

enum Cleanup {
    static func dictate(_ raw: String, style: StylePreset, settings s: QuillSettings) async -> String {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if let snip = TextTools.wholeUtteranceSnippet(raw, s.snippets) { return snip }
        if s.cleanupEnabled, let key = Keychain.apiKey {
            do {
                let out = try await ClaudeClient(apiKey: key, model: s.claudeModel)
                    .complete(system: TextTools.dictationSystem(s, style: style), user: "<transcript>\n\(raw)\n</transcript>")
                return TextTools.finish(out, s)
            } catch {
                print("Cleanup failed, using raw text: \(error)")
            }
        }
        return TextTools.finish(TextTools.localFormat(raw), s)
    }

    static func command(_ instruction: String, selection: String, style: StylePreset, settings s: QuillSettings) async throws -> String {
        guard let key = Keychain.apiKey else {
            throw ClaudeClient.APIError(message: "Add your Claude API key in Quill to use Rewrite.")
        }
        var user = "<instruction>\n\(instruction)\n</instruction>"
        if !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            user = "<selected>\n\(selection)\n</selected>\n" + user
        }
        let out = try await ClaudeClient(apiKey: key, model: s.claudeModel)
            .complete(system: TextTools.commandSystem(s, style: style), user: user)
        return TextTools.finish(out, s)
    }
}

// MARK: - Whisper (on-device)

actor Transcriber {
    private var kit: WhisperKit?
    private var loadedModel: String?

    var isReady: Bool { kit != nil }

    func load(model: String) async throws {
        if kit != nil, loadedModel == model { return }
        kit = nil
        // Neural Engine + CPU only: the GPU isn't available to apps running in the background.
        let compute = ModelComputeOptions(
            melCompute: .cpuAndNeuralEngine,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly
        )
        let config = WhisperKitConfig(model: model.isEmpty ? nil : model, computeOptions: compute,
                                      verbose: false, prewarm: true, load: true, download: true)
        kit = try await WhisperKit(config)
        loadedModel = model
    }

    func transcribe(_ samples: [Float], prompt: String) async throws -> String {
        guard let kit else { return "" }
        var opts = DecodingOptions()
        opts.language = "en"
        opts.skipSpecialTokens = true
        opts.withoutTimestamps = true
        if !prompt.isEmpty, let tok = kit.tokenizer {
            opts.promptTokens = tok.encode(text: " " + prompt).filter { $0 < tok.specialTokens.specialTokenBegin }
            opts.usePrefillPrompt = true
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: opts)
        return results.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
