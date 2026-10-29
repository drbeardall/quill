import SwiftUI

private let accent = Color(red: 0.24, green: 0.31, blue: 0.85)

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @State private var deleteTimer: Timer?

    var body: some View {
        VStack(spacing: 8) {
            if model.showSnippets {
                snippetList
            } else {
                styleRow
                micRow
            }
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(height: 262)
    }

    // MARK: Rows

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StylePreset.allCases) { st in
                    Button { model.setStyle(st) } label: {
                        Text(st.label).font(.footnote.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(model.style == st ? Color.white : Color.primary)
                            .background(model.style == st ? accent : Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 32)
    }

    private var micRow: some View {
        HStack(alignment: .center) {
            sideButton(icon: "wand.and.stars", label: model.hasSelection ? "Rewrite" : "Write") {
                model.micTapped(mode: .command)
            }
            .disabled(model.phase == .processing)
            Spacer()
            VStack(spacing: 6) {
                Button { model.micTapped() } label: {
                    ZStack {
                        Circle().fill(micColor).frame(width: 84, height: 84)
                        switch model.phase {
                        case .processing, .opening:
                            ProgressView().tint(.white).scaleEffect(1.3)
                        case .listening:
                            Image(systemName: "stop.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        default:
                            Image(systemName: "mic.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.phase == .listening ? "Finish dictation" : "Start dictation")
                Text(statusText).font(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 230)
            }
            Spacer()
            deleteKey
        }
        .frame(maxHeight: .infinity)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.needsGlobe {
                key(icon: "globe", width: 44) { model.nextKeyboard() }
            }
            key(icon: "text.badge.plus", width: 44) { model.showSnippets.toggle() }
            Button { model.insert(" ") } label: {
                Text("space").font(.callout).frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
            }
            .buttonStyle(.plain)
            key(text: ".", width: 40) { model.insert(".") }
            key(icon: "return", width: 64) { model.insert("\n") }
        }
    }

    private var snippetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Snippets").font(.subheadline.bold())
                Spacer()
                Button("Done") { model.showSnippets = false }.font(.subheadline)
            }
            .padding(.horizontal, 6).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.snippets.filter { !$0.trigger.isEmpty }) { s in
                        Button { model.insertSnippet(s) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.trigger).font(.subheadline.weight(.semibold))
                                Text(s.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    if model.snippets.isEmpty {
                        Text("Add snippets in the Quill app.").font(.footnote).foregroundStyle(.secondary).padding()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Pieces

    private var deleteKey: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 20))
            .frame(width: 64, height: 54)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { model.backspace() }
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                if !pressing { deleteTimer?.invalidate(); deleteTimer = nil }
            }, perform: {
                deleteTimer?.invalidate()
                deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    Task { @MainActor in model.backspace() }
                }
            })
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
    }

    private func sideButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.caption2)
            }
            .frame(width: 64, height: 54)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func key(icon: String? = nil, text: String? = nil, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Image(systemName: icon) } else { Text(text ?? "") }
            }
            .font(.system(size: 17))
            .frame(width: width, height: 42)
            .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var micColor: Color {
        switch model.phase {
        case .listening: return .red
        case .error: return .gray
        default: return accent
        }
    }

    private var isError: Bool { if case .error = model.phase { return true } else { return false } }

    private var statusText: String {
        switch model.phase {
        case .idle: return model.sessionAlive ? "Tap to talk" : "Tap to talk (opens Quill the first time)"
        case .opening: return "Opening Quill… then tap ◀ to come back"
        case .listening: return "Listening… tap to finish"
        case .processing: return "Writing…"
        case .error(let m): return m
        }
    }
}
