import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!

    override func viewDidLoad() {
        super.viewDidLoad()
        model = KeyboardModel(controller: self)
        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appeared()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.disappeared()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        model.refreshSelection()
    }

    /// Keyboards can't call UIApplication.open, so walk the responder chain to the host app's
    /// UIApplication and call open(_:options:completionHandler:) on it dynamically.
    func openContainerApp(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector), r !== self {
                typealias OpenFn = @convention(c) (NSObject, Selector, NSURL, NSDictionary, Any?) -> Void
                let fn = unsafeBitCast(r.method(for: selector), to: OpenFn.self)
                fn(r, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = r.next
        }
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    enum Phase: Equatable { case idle, opening, listening, processing, error(String) }

    @Published var phase: Phase = .idle
    @Published var style: StylePreset
    @Published var snippets: [Snippet]
    @Published var showSnippets = false
    @Published var hasSelection = false
    @Published var sessionAlive = false

    weak var controller: KeyboardViewController?
    private var poll: Timer?
    private var activeJob: UUID?
    private var insertedJobs = Set<UUID>()

    init(controller: KeyboardViewController) {
        self.controller = controller
        let s = QuillSettings.load()
        style = s.style
        snippets = s.snippets
    }

    var needsGlobe: Bool { controller?.needsInputModeSwitchKey ?? true }
    var hasFullAccess: Bool { controller?.hasFullAccess ?? false }
    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    func appeared() {
        let s = QuillSettings.load()
        snippets = s.snippets
        style = s.style
        refreshSelection()
        Bridge.observe(Bridge.changedNote) { [weak self] in self?.check() }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        check()
    }

    func disappeared() {
        poll?.invalidate()
        poll = nil
    }

    func refreshSelection() {
        hasSelection = !(proxy?.selectedText ?? "").isEmpty
    }

    // MARK: Mic

    func micTapped(mode: JobMode = .dictate) {
        switch phase {
        case .listening:
            Bridge.post(Bridge.stopNote)
            phase = .processing
        case .processing, .opening:
            Bridge.post(Bridge.cancelNote)
            Bridge.update { $0.state = .cancelled }
            phase = .idle
        case .idle, .error:
            start(mode: mode)
        }
    }

    private func start(mode: JobMode) {
        guard hasFullAccess else {
            phase = .error("Turn on Allow Full Access: Settings › General › Keyboard › Keyboards › Quill.")
            return
        }
        var job = Job()
        job.mode = mode
        job.style = style
        job.selection = mode == .command ? (proxy?.selectedText ?? "") : ""
        Bridge.job = job
        activeJob = job.id
        if Bridge.sessionAlive {
            Bridge.post(Bridge.startNote)
            phase = .listening  // confirmed by check() once the app picks it up
        } else {
            phase = .opening
            controller?.openContainerApp(URL(string: "quill://dictate")!)
        }
    }

    private func check() {
        sessionAlive = Bridge.sessionAlive
        refreshSelection()
        guard let id = activeJob, let job = Bridge.job, job.id == id else { return }
        switch job.state {
        case .requested:
            if phase == .listening, !sessionAlive { phase = .opening }
        case .listening:
            phase = .listening
        case .processing:
            phase = .processing
        case .done:
            if !insertedJobs.contains(id) {
                insertedJobs.insert(id)
                if !job.text.isEmpty { proxy?.insertText(spaced(job.text, replacing: job.mode == .command)) }
            }
            activeJob = nil
            phase = .idle
        case .failed:
            activeJob = nil
            phase = .error(job.error.isEmpty ? "Something went wrong." : job.error)
        case .cancelled:
            activeJob = nil
            phase = .idle
        }
    }

    /// Add a space before dictated text when it follows a word.
    private func spaced(_ text: String, replacing: Bool) -> String {
        guard !replacing, let before = proxy?.documentContextBeforeInput, let last = before.last else { return text }
        if last.isWhitespace || "([{\"'“‘/".contains(last) { return text }
        if let first = text.first, ".,;:!?)".contains(first) { return text }
        return " " + text
    }

    // MARK: Keys

    func insert(_ s: String) { proxy?.insertText(s) }
    func backspace() { proxy?.deleteBackward() }
    func nextKeyboard() { controller?.advanceToNextInputMode() }

    func insertSnippet(_ s: Snippet) {
        proxy?.insertText(s.text)
        showSnippets = false
    }

    func setStyle(_ st: StylePreset) {
        style = st
        var s = QuillSettings.load()
        s.style = st
        s.save()
    }
}
