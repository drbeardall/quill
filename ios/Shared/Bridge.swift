import Foundation

/// How the keyboard and the app talk to each other.
///
/// iOS keyboards can't use the microphone, so the keyboard asks the Quill app to listen.
/// While a "session" is active the app keeps its microphone open in the background (orange dot)
/// and updates a heartbeat. The keyboard writes a Job, pings the app with a Darwin notification,
/// and watches the Job's state until the cleaned text is ready to insert.
enum JobMode: String, Codable { case dictate, command }
enum JobState: String, Codable { case requested, listening, processing, done, failed, cancelled }

struct Job: Codable, Equatable {
    var id = UUID()
    var mode: JobMode = .dictate
    var style: StylePreset = .clean
    var selection = ""
    var state: JobState = .requested
    var text = ""
    var error = ""
    var updated = Date()
}

enum Bridge {
    static let startNote = "com.drbeardall.quill.start"
    static let stopNote = "com.drbeardall.quill.stop"
    static let cancelNote = "com.drbeardall.quill.cancel"
    static let changedNote = "com.drbeardall.quill.changed"

    private static let jobKey = "bridge.job"
    private static let heartbeatKey = "bridge.heartbeat"
    private static let sessionEndKey = "bridge.sessionEnds"

    static var job: Job? {
        get {
            guard let d = AppGroup.defaults.data(forKey: jobKey) else { return nil }
            return try? JSONDecoder().decode(Job.self, from: d)
        }
        set {
            if var j = newValue {
                j.updated = Date()
                AppGroup.defaults.set(try? JSONEncoder().encode(j), forKey: jobKey)
            } else {
                AppGroup.defaults.removeObject(forKey: jobKey)
            }
        }
    }

    static func update(_ change: (inout Job) -> Void) {
        guard var j = job else { return }
        change(&j)
        job = j
        post(changedNote)
    }

    // Session liveness (written by the app about once a second).
    static func beat(sessionEnds: Date) {
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
        AppGroup.defaults.set(sessionEnds.timeIntervalSince1970, forKey: sessionEndKey)
    }

    static func endSession() {
        AppGroup.defaults.set(0, forKey: heartbeatKey)
        AppGroup.defaults.set(0, forKey: sessionEndKey)
    }

    static var sessionAlive: Bool {
        Date().timeIntervalSince1970 - AppGroup.defaults.double(forKey: heartbeatKey) < 2.5
    }

    static var sessionEnds: Date? {
        let t = AppGroup.defaults.double(forKey: sessionEndKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: Darwin notifications (cross-process pings, no payload)

    private static var handlers: [String: () -> Void] = [:]

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    private static let token = NSObject()

    static func observe(_ name: String, _ handler: @escaping () -> Void) {
        let isNew = handlers[name] == nil
        handlers[name] = handler
        guard isNew else { return }  // register each name once; later calls just swap the handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(token).toOpaque(),
            { _, _, cfName, _, _ in
                guard let cf = cfName else { return }
                let n = cf.rawValue as String
                DispatchQueue.main.async { Bridge.handlers[n]?() }
            },
            name as CFString, nil, .deliverImmediately)
    }
}
