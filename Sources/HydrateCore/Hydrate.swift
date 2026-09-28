import Foundation

public let version = "1.0.0"

public struct Options: Equatable {
    public var dryRun = false
    public var timeout: Double = 60
    public var jobs = 4
    public var help = false
    public var showVersion = false
    public var paths: [String] = []
    public init() {}
}

public enum UsageError: Error, Equatable {
    case unknownFlag(String)
    case missingValue(String)
    case badNumber(flag: String, value: String)
}

let usage = """
    dropbox-hydrate-bin \(version) — download Dropbox "online only" placeholders, headless.

    usage: dropbox-hydrate-bin [--dry-run] [--timeout SEC] [--jobs N] [PATH ...]

      PATH           files and/or folders (folders recursively); default: .
      --dry-run      only list the placeholders (0-byte files), download nothing
      --timeout SEC  max seconds to wait per file (default 60)
      --jobs N       files downloaded at the same time (default 4)
      --version      print the version
      -h, --help     this text

    How: a coordinated read (NSFileCoordinator) per 0-byte file makes the Dropbox
    app download it. No app is launched, no window, no dialog. A plain read does not work.

    Exit: 0 = all local, 1 = some files stayed empty (listed on stderr), 2 = usage error.

    macOS only. Elsewhere:
      Windows  reading a placeholder downloads it; for a whole folder use
               attrib +P "<folder>" /s /d   ("Always keep on this device"),
               or Explorer: right-click > "Make available offline".
      Linux    Dropbox has no online-only files on Linux: a 0-byte file is really empty
               or excluded by selective sync (see: dropbox exclude list).
    """

/// Parses the command line. Paths are not checked here; `run` does that.
public func parse(_ args: [String]) throws -> Options {
    var o = Options()
    var rest = args[...]
    while let arg = rest.popFirst() {
        switch arg {
        case "--dry-run": o.dryRun = true
        case "-h", "--help": o.help = true
        case "--version": o.showVersion = true
        case "--timeout":
            guard let v = rest.popFirst() else { throw UsageError.missingValue(arg) }
            guard let n = Double(v), n > 0 else { throw UsageError.badNumber(flag: arg, value: v) }
            o.timeout = n
        case "--jobs":
            guard let v = rest.popFirst() else { throw UsageError.missingValue(arg) }
            guard let n = Int(v), n > 0 else { throw UsageError.badNumber(flag: arg, value: v) }
            o.jobs = n
        default:
            if arg.hasPrefix("-") { throw UsageError.unknownFlag(arg) }
            o.paths.append(arg)
        }
    }
    if o.paths.isEmpty { o.paths = ["."] }
    return o
}

/// A placeholder is a regular file (not a symlink) with 0 bytes.
public func isPlaceholder(_ path: String) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
    return attrs[.type] as? FileAttributeType == .typeRegular && (attrs[.size] as? Int) == 0
}

func isSkippedName(_ name: String) -> Bool {
    name.hasPrefix(".") || name.hasPrefix("~$")
}

/// All placeholders under the given paths: folders recursively (hidden folders, hidden files
/// and Office lock files skipped), named files as they are. Sorted, without duplicates.
public func collect(_ paths: [String]) -> [String] {
    var found = Set<String>()
    for path in paths {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
        if !isDir.boolValue {
            if isPlaceholder(path) { found.insert(path) }
            continue
        }
        let walker = FileManager.default.enumerator(atPath: path)
        while let relative = walker?.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            let full = (path as NSString).appendingPathComponent(relative)
            if isSkippedName(name) {
                if (walker?.fileAttributes?[.type] as? FileAttributeType) == .typeDirectory {
                    walker?.skipDescendants()
                }
                continue
            }
            if isPlaceholder(full) { found.insert(full) }
        }
    }
    return found.sorted()
}

/// Downloads one file: a coordinated read, the call Dropbox reacts to.
public typealias Materializer = @Sendable (String) -> Void

/// The real materializer. Read-only: it reads at most one byte inside the coordination.
public func coordinatedRead(_ path: String) {
    var error: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
        readingItemAt: URL(fileURLWithPath: path), options: [], error: &error
    ) { url in
        let handle = try? FileHandle(forReadingFrom: url)
        _ = try? handle?.read(upToCount: 1)
        try? handle?.close()
    }
}

/// Runs `materialize` for every file, at most `jobs` at a time, each with `timeout` seconds.
/// A file counts as local when it has bytes afterwards.
public func hydrate(
    _ files: [String], jobs: Int, timeout: Double, materialize: @escaping Materializer
) -> (local: [String], empty: [String]) {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = jobs
    for file in files {
        queue.addOperation {
            let done = DispatchSemaphore(value: 0)
            // Own thread per file: a hanging download must not block the queue past its timeout.
            Thread.detachNewThread {
                materialize(file)
                done.signal()
            }
            _ = done.wait(timeout: .now() + timeout)
        }
    }
    queue.waitUntilAllOperationsAreFinished()
    let local = files.filter { !isPlaceholder($0) }
    return (local, files.filter(isPlaceholder))
}

/// The whole CLI. Returns the exit code.
public func run(
    _ args: [String], out: (String) -> Void, err: (String) -> Void,
    materialize: @escaping Materializer = coordinatedRead
) -> Int32 {
    let o: Options
    do {
        o = try parse(args)
    } catch {
        err("dropbox-hydrate-bin: \(error) — see --help")
        return 2
    }
    if o.help {
        out(usage)
        return 0
    }
    if o.showVersion {
        out(version)
        return 0
    }
    let missing = o.paths.filter { !FileManager.default.fileExists(atPath: $0) }
    if !missing.isEmpty {
        err("dropbox-hydrate-bin: no such file or folder: \(missing.joined(separator: ", "))")
        return 2
    }

    let files = collect(o.paths)
    if files.isEmpty {
        out("Nothing to do — all files are local.")
        return 0
    }
    out("\(files.count) placeholder(s) found.")
    if o.dryRun {
        files.forEach { out("  \($0)") }
        return 0
    }

    let result = hydrate(files, jobs: o.jobs, timeout: o.timeout, materialize: materialize)
    out("\(result.local.count)/\(files.count) local.")
    if result.empty.isEmpty { return 0 }
    err("\(result.empty.count) file(s) stayed empty (really empty, offline, or timed out):")
    result.empty.forEach { err("  \($0)") }
    return 1
}
