import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var session: DictationSession
    @State private var keyField = ""
    @State private var keyMessage = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { SetupGuideView() } label: {
                        Label("Set up the Quill keyboard", systemImage: "keyboard.badge.ellipsis")
                    }
                }

                Section {
                    Toggle("Clean up with Claude", isOn: $store.s.cleanupEnabled)
                    Picker("Claude model", selection: $store.s.claudeModel) {
                        Text("Haiku (fast)").tag("claude-haiku-5-5")
                        Text("Sonnet (smarter)").tag("claude-sonnet-5-5")
                    }
                    if store.apiKeySet {
                        LabeledContent("API key", value: "Saved in Keychain")
                        HStack {
                            Button(testing ? "Testing…" : "Test key") { testKey() }.disabled(testing)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                Keychain.apiKey = nil; store.apiKeySet = false; keyMessage = ""
                            }
                        }
                    } else {
                        SecureField("Paste API key (sk-ant-…)", text: $keyField)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Save key") { saveKey() }.disabled(keyField.isEmpty)
                        Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    }
                    if !keyMessage.isEmpty { Text(keyMessage).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("AI cleanup")
                } footer: {
                    Text("Removes “um”s, fixes punctuation and applies your dictionary and style. Off = raw transcript and nothing leaves your iPhone. The API is billed per use, separate from a Claude subscription.")
                }

                Section {
                    Picker("Default style", selection: $store.s.style) {
                        ForEach(StylePreset.allCases) { Text($0.label).tag($0) }
                    }
                    NavigationLink { DictionaryView() } label: {
                        LabeledContent("Dictionary", value: "\(store.s.words.count) words")
                    }
                    NavigationLink { SnippetsView() } label: {
                        LabeledContent("Snippets", value: "\(store.s.snippets.count)")
                    }
                } header: { Text("Writing") }

                Section {
                    Picker("Whisper model", selection: $store.s.whisperModel) {
                        Text("Best for this iPhone").tag("")
                        Text("Small (English)").tag("small.en")
                        Text("Base (English, fastest)").tag("base.en")
                    }
                    .onChange(of: store.s.whisperModel) { _, _ in session.loadModel() }
                    LabeledContent("Status", value: modelStatus)
                    Stepper("Keyboard session: \(store.s.sessionMinutes) min", value: $store.s.sessionMinutes, in: 1...30)
                    Toggle("Haptics", isOn: $store.s.haptics)
                } header: {
                    Text("Speech")
                } footer: {
                    Text("Speech recognition runs on your iPhone. During a keyboard session Quill keeps the microphone ready in the background (you'll see the orange dot), so you can dictate without leaving your app.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var modelStatus: String {
        switch session.modelState {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Ready"
        case .failed: return "Failed (see Dictate tab)"
        }
    }

    private func saveKey() {
        let k = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.hasPrefix("sk-") else { keyMessage = "That doesn't look like an Anthropic key (it starts with sk-ant-)."; return }
        Keychain.apiKey = k
        keyField = ""
        store.apiKeySet = true
        keyMessage = "Saved."
    }

    private func testKey() {
        guard let key = Keychain.apiKey else { return }
        testing = true
        let model = store.s.claudeModel
        Task {
            do {
                _ = try await ClaudeClient(apiKey: key, model: model).complete(system: "Reply with OK.", user: "OK?", maxTokens: 5)
                keyMessage = "Key works ✓"
            } catch {
                keyMessage = "Key test failed: \(error.localizedDescription)"
            }
            testing = false
        }
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a word or phrase", text: $newWord).onSubmit(add)
                    Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(store.s.words, id: \.self) { Text($0) }
                    .onDelete { store.s.words.remove(atOffsets: $0) }
            } header: { Text("Always spell right") } footer: {
                Text("Names, drug names and billing terms. These also help the speech model hear them correctly.")
            }

            Section {
                ForEach($store.s.replacements) { $r in
                    HStack {
                        TextField("When it hears", text: $r.heard).textInputAutocapitalization(.never)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Write", text: $r.write)
                    }
                }
                .onDelete { store.s.replacements.remove(atOffsets: $0) }
                Button { store.s.replacements.append(Replacement(heard: "", write: "")) } label: {
                    Label("Add replacement", systemImage: "plus")
                }
            } header: { Text("Always replace") }
        }
        .navigationTitle("Dictionary")
        .toolbar { EditButton() }
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !store.s.words.contains(w) else { return }
        store.s.words.append(w)
        newWord = ""
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("Say the trigger phrase and Quill types the saved text, on its own (“clinic signature”) or mid-sentence (“send it to my clinic address”). They also appear in the keyboard’s snippet list.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach($store.s.snippets) { $snip in
                Section {
                    TextField("Trigger phrase", text: $snip.trigger).font(.headline).textInputAutocapitalization(.never)
                    TextField("Text to insert", text: $snip.text, axis: .vertical).lineLimit(2...8)
                    Button("Delete snippet", role: .destructive) {
                        store.s.snippets.removeAll { $0.id == snip.id }
                    }
                }
            }
            Section {
                Button { store.s.snippets.append(Snippet(trigger: "", text: "")) } label: {
                    Label("New snippet", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Snippets")
    }
}

// MARK: - Keyboard setup guide

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                step(1, "Open Settings", "Tap the button below. It opens Quill's page in the Settings app.")
                step(2, "Keyboards", "Tap Keyboards and turn on Quill.")
                step(3, "Allow Full Access", "Turn on Allow Full Access. Quill needs it so the keyboard can hand your words to the Quill app. Your keystrokes aren't recorded or sent anywhere.")
                step(4, "Use it", "In any app, tap and hold 🌐 (or the keyboard icon) and pick Quill. Tap the mic, talk, tap again to insert.")
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { Label("Open Settings", systemImage: "gear") }
            }
            Section("Good to know") {
                Text("The first time you tap the mic, iPhone switches to the Quill app for a second to turn the microphone on. Tap the ◀ in the top-left corner to go back, then talk. For the next few minutes, the mic works right inside the keyboard.")
                Text("Select text first and tap Rewrite to change it by voice, e.g. “make this more formal”.")
            }
            .font(.footnote)
        }
        .navigationTitle("Keyboard setup")
    }

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color.quill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
