import Foundation

public final class DbgLggr: @unchecked Sendable {
    public static let shared = DbgLggr()

    private var stream: FileStream?
    private var handle: FileHandle?
    private let queue = DispatchQueue(label: "DbgLggr.serial", qos: .utility)
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    private struct FileStream: TextOutputStream {
        private let handle: FileHandle

        init(handle: FileHandle) {
            self.handle = handle
        }

        mutating func write(_ string: String) {
            guard let data = string.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    public func open(url: URL = DbgLggr.defaultLogURL()) {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
            stream = nil

            do {
                try Data().write(to: url, options: .atomic)
            } catch {
                let msg = "[DbgLggr] Cannot create/truncate \(url.path): \(error)\n"
                _ = msg.withCString { cstr in
                    write(STDERR_FILENO, cstr, strlen(cstr))
                }
                return
            }

            do {
                let h = try FileHandle(forWritingTo: url)
                handle = h
                stream = FileStream(handle: h)
            } catch {
                let msg = "[DbgLggr] Cannot open \(url.path): \(error)\n"
                _ = msg.withCString { cstr in
                    write(STDERR_FILENO, cstr, strlen(cstr))
                }
                return
            }

            self.writeLocked(
                "=== Log opened: \(url.path) ===",
                file: #fileID,
                line: #line,
                function: #function
            )
        }
    }

    public func close() {
        queue.sync {
            guard let h = handle else { return }
            writeSummaryLocked()
            try? h.synchronize()
            try? h.close()
            handle = nil
            stream = nil
        }
    }

    private func writeSummaryLocked() {
        guard var s = stream else { return }

        guard Glbls.debugOn else {
            s.write("\n=== Debugging is turned off. ===\n")
            stream = s
            return
        }

        let tms = Glbls.debugTms
        guard !tms.isEmpty else { return }

        let totalNs = tms.values.reduce(Duration.zero, +)
        let totalDouble = Double(totalNs.components.seconds) * 1e9
                        + Double(totalNs.components.attoseconds) / 1e9

        let sorted = tms.sorted { a, b in
            let aNs = Double(a.value.components.seconds) * 1e9 + Double(a.value.components.attoseconds) / 1e9
            let bNs = Double(b.value.components.seconds) * 1e9 + Double(b.value.components.attoseconds) / 1e9
            return aNs > bNs
        }

        func pad(_ str: String, _ width: Int) -> String {
            str.padding(toLength: max(str.count, width), withPad: " ", startingAt: 0)
        }

        s.write("\n=== Debug timing summary ===\n")
        s.write("\(pad("location", 30)) \(String(format: "%10s  %6s", "ms", "%"))\n")
        s.write(String(repeating: "-", count: 52) + "\n")

        for entry in sorted {
            let entryNs = Double(entry.value.components.seconds) * 1e9
                        + Double(entry.value.components.attoseconds) / 1e9
            let pct = totalDouble > 0 ? entryNs / totalDouble * 100.0 : 0.0
            let ms = entryNs / 1_000_000.0
            let loc = "\(entry.key.file):\(entry.key.line)"
            s.write("\(pad(loc, 30)) \(String(format: "%10.3f  %5.1f%%", ms, pct))\n")
        }

        s.write("\(pad("TOTAL", 30)) \(String(format: "%10.3f ms", totalDouble / 1_000_000.0))\n")
        s.write("============================\n")
        stream = s
    }

    public func log(_ message: String, file: String, line: Int, function: String) {
        queue.sync {
            writeLocked(message, file: file, line: line, function: function)
        }
    }

    private func writeLocked(_ message: String, file: String, line: Int, function: String) {
        guard var s = stream, handle != nil else { return }

        let start = ContinuousClock.now

        let ts = formatter.string(from: Date())
        let base = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let text = "\(ts) \(base)(\(line)): \(function), \(message)\n"

        s.write(text)
        stream = s

        let key = DebugKey(file: base, line: line)
        Glbls.debugTms[key, default: .zero] += ContinuousClock.now - start
    }

    public static func defaultLogURL() -> URL {
        URL(fileURLWithPath: "/home/Dropbox/programming/Swift/TwosCmplt/debug.log")
    }
}

@inline(__always)
public func dbg(
    _ message: @autoclosure () -> String = "",
    file: String     = #fileID,
    line: Int        = #line,
    function: String = #function
) {
    if !Glbls.debugOn {
        return
    }
    DbgLggr.shared.log(message(), file: file, line: line, function: function)
}
