import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var session = DictationSession.shared
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(store)
                .tint(Color.quill)
                .onOpenURL { session.handleURL($0) }
                .task { session.loadModel() }
        }
    }
}

/// Observable wrapper that saves settings to the App Group on every change.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var s: QuillSettings = QuillSettings.load() {
        didSet { if s != oldValue { s.save() } }
    }
    @Published var apiKeySet = Keychain.apiKey != nil
}

extension Color {
    static let quill = Color(red: 0.24, green: 0.31, blue: 0.85)
}

struct RootView: View {
    var body: some View {
        TabView {
            DictateView().tabItem { Label("Dictate", systemImage: "mic.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Dictate tab

struct DictateView: View {
    @EnvironmentObject var session: DictationSession
    @EnvironmentObject var store: SettingsStore
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if session.cameFromKeyboard && session.sessionActive {
                        backBanner
                    }
                    modelBanner
                    micButton
                    stylePicker
                    if !session.lastText.isEmpty { resultCard }
                    if !session.lastError.isEmpty {
                        Text(session.lastError).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    sessionCard
                }
                .padding()
            }
            .navigationTitle("Quill")
        }
    }

    private var backBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.recording ? "Listening… go back and talk" : "Quill is listening for your keyboard").font(.headline)
                Text("Tap the ◀ app name in the top-left corner to return to where you were typing.").font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .background(Color.quill, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var modelBanner: some View {
        switch session.modelState {
        case .loading:
            Label("Getting the speech model ready… The first time downloads it (a few hundred MB), so stay on Wi-Fi.", systemImage: "arrow.down.circle")
                .font(.footnote).foregroundStyle(.secondary).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Label("Speech model didn't load", systemImage: "exclamationmark.triangle").font(.subheadline.bold())
                Text(msg).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { session.loadModel() }.buttonStyle(.bordered)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        default: EmptyView()
        }
    }

    private var micButton: some View {
        VStack(spacing: 10) {
            Button { session.toggleInApp() } label: {
                ZStack {
                    Circle().fill(session.recording ? Color.red : Color.quill)
                        .frame(width: 132, height: 132)
                        .shadow(color: (session.recording ? Color.red : Color.quill).opacity(0.35), radius: 18, y: 8)
                    if session.processing {
                        ProgressView().tint(.white).scaleEffect(1.6)
                    } else {
                        Image(systemName: session.recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 46, weight: .semibold)).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(session.processing)
            .accessibilityLabel(session.recording ? "Stop dictation" : "Start dictation")
            Text(session.recording ? "Listening… tap to finish" : session.processing ? "Cleaning up…" : "Tap to dictate")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var stylePicker: some View {
        Picker("Style", selection: $store.s.style) {
            ForEach(StylePreset.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.lastText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button {
                    UIPasteboard.general.string = session.lastText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderedProminent)
                ShareLink(item: session.lastText) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) { session.lastText = "" } label: { Image(systemName: "trash") }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keyboard", systemImage: "keyboard").font(.headline)
            if session.sessionActive, let ends = session.sessionEnds {
                HStack {
                    Text("Listening for the Quill keyboard until \(ends.formatted(date: .omitted, time: .shortened)).")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { session.endSession() }.buttonStyle(.bordered)
                }
            } else {
                Text("Switch to the Quill keyboard in any app and tap the mic. The first tap opens Quill for a moment; after that it works right in place for \(store.s.sessionMinutes) minutes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
