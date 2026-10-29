import Foundation

/// Shared between the Quill app and the Quill keyboard through the App Group.
enum AppGroup {
    static let id = "group.com.drbeardall.quill"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

struct Replacement: Codable, Hashable, Identifiable {
    var id = UUID()
    var heard: String
    var write: String
}

struct Snippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: String
    var text: String
}

enum StylePreset: String, Codable, CaseIterable, Identifiable {
    case clean, formal, casual, veryCasual, clinical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: return "Clean"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Texting"
        case .clinical: return "Clinical"
        }
    }

    var instruction: String {
        switch self {
        case .clean:
            return "Neutral, clean writing. Full sentences, standard capitalization and punctuation."
        case .formal:
            return "Professional email register. Full sentences, proper capitalization and punctuation, paragraph breaks between ideas. Do not add a greeting or sign-off unless the speaker said one."
        case .casual:
            return "Casual chat message. Light punctuation, sentence case, no trailing period on a single short sentence. Keep contractions."
        case .veryCasual:
            return "Very casual text message. Mostly lowercase, minimal punctuation, keep it short. Keep contractions and slang as spoken."
        case .clinical:
            return "Concise clinical chart-note style. Keep medical terminology, abbreviations and numbers exactly as dictated (e.g. ROM, VAS 6/10, C5-C6). Use short declarative sentences; use line breaks for spoken headings such as Subjective, Objective, Assessment, Plan."
        }
    }
}

struct QuillSettings: Codable, Equatable {
    var cleanupEnabled = true
    var claudeModel = "claude-haiku-5-5"
    /// "" = best model for this iPhone (WhisperKit decides), otherwise e.g. "small.en".
    var whisperModel = ""
    var style: StylePreset = .clean
    var sessionMinutes = 5
    var haptics = true
    var words: [String] = [
        "SAIF", "Canby", "Beardall", "L.Ac.", "chiropractic", "acupuncture", "subluxation",
        "cervicothoracic", "lumbosacral", "paraspinal", "Medicare", "CPT", "ICD-10", "Knights of Columbus",
    ]
    var replacements: [Replacement] = [
        Replacement(heard: "safe corporation", write: "SAIF Corporation"),
        Replacement(heard: "dr b", write: "Dr. B"),
    ]
    var snippets: [Snippet] = [
        Snippet(trigger: "clinic address", text: "725 SE 1st Ave., Canby, OR 97013"),
        Snippet(trigger: "clinic phone", text: "Ph: 503-266-9300 | Fax: 503-213-6020"),
        Snippet(trigger: "clinic signature", text: "Christopher Alan Beardall, DC, L.Ac.\nBeardall Acupuncture & Chiropractic Clinic, PC\n725 SE 1st Ave., Canby, OR 97013\nPh: 503-266-9300 | Fax: 503-213-6020"),
    ]

    private static let key = "settings.v1"

    static func load() -> QuillSettings {
        guard let data = AppGroup.defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(QuillSettings.self, from: data) else { return QuillSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
}
