import Foundation
import XCTest

@testable import HydrateCore

/// The Dropbox daemon is the boundary: in tests it is replaced by a materializer that
/// writes bytes into the file, just like Dropbox does when it downloads a placeholder.
let fakeDropbox: Materializer = { path in
    try? Data("downloaded".utf8).write(to: URL(fileURLWithPath: path))
}

/// Counts how many materializer calls run at the same time.
final class ConcurrencyGauge: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var peak = 0

    func enter() {
        lock.lock()
        active += 1
        peak = max(peak, active)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        active -= 1
        lock.unlock()
    }
}

final class HydrateCoreTests: XCTestCase {
    var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "hydrate-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    @discardableResult
    func file(_ name: String, _ content: String = "") -> String {
        let path = dir + "/" + name
        try! FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(content.utf8))
        return path
    }

    func size(_ path: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? -1
    }

    struct Run {
        var code: Int32
        var out: [String]
        var err: [String]
    }

    func runCLI(_ args: [String], _ materialize: @escaping Materializer = fakeDropbox) -> Run {
        var out: [String] = []
        var err: [String] = []
        let code = HydrateCore.run(
            args, out: { out.append($0) }, err: { err.append($0) }, materialize: materialize)
        return Run(code: code, out: out, err: err)
    }

    // S1
    func testEmptyRegularFileIsPlaceholder() {
        XCTAssertTrue(isPlaceholder(file("a.pdf")))
    }

    // S2
    func testNonEmptySymlinkDirectoryAndMissingAreNotPlaceholders() throws {
        XCTAssertFalse(isPlaceholder(file("full.pdf", "bytes")))
        let target = file("target.pdf")
        let link = dir + "/link.pdf"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertFalse(isPlaceholder(link))
        try FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: true)
        XCTAssertFalse(isPlaceholder(dir + "/sub"))
        XCTAssertFalse(isPlaceholder(dir + "/missing.pdf"))
    }

    // S3
    func testDirectoryWalkIsRecursiveAndSkipsHiddenAndOfficeLockFiles() {
        let deep = file("a/b/deep.docx")
        let top = file("top.xlsx")
        file("full.pdf", "bytes")
        file(".hidden.pdf")
        file("~$lock.docx")
        file(".git/objects/x")
        XCTAssertEqual(collect([dir]), [deep, top].sorted())
    }

    // S4
    func testExplicitHiddenFileIsCounted() {
        let hidden = file(".notes.md")
        XCTAssertEqual(collect([hidden]), [hidden])
    }

    // S5
    func testDuplicatesAreCountedOnceAndSorted() {
        let b = file("b.pdf")
        let a = file("a.pdf")
        XCTAssertEqual(collect([b, dir, a]), [a, b])
    }

    // S6
    func testDryRunListsAndNeverCallsTheMaterializer() {
        let a = file("a.pdf")
        let r = runCLI(["--dry-run", dir]) { _ in XCTFail("materializer called in dry run") }
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains { $0.contains(a) })
        XCTAssertEqual(size(a), 0)
    }

    // S7
    func testNothingToDo() {
        file("full.pdf", "bytes")
        let r = runCLI([dir])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.joined().lowercased().contains("nothing to do"))
    }

    // S8
    func testAllPlaceholdersHydratedExitsZero() {
        let a = file("a.pdf")
        let b = file("sub/b.docx")
        let r = runCLI([dir])
        XCTAssertEqual(r.code, 0)
        XCTAssertGreaterThan(size(a), 0)
        XCTAssertGreaterThan(size(b), 0)
        XCTAssertTrue(r.out.joined(separator: "\n").contains("2/2"))
    }

    // S9
    func testFilesThatStayEmptyExitOneAndAreListedOnStderr() {
        let good = file("good.pdf")
        let stays = file("really-empty.txt")
        let r = runCLI([dir]) { path in if path == good { fakeDropbox(path) } }
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.err.contains { $0.contains(stays) })
        XCTAssertFalse(r.err.contains { $0.contains(good) })
    }

    // S10
    func testHangingFileTimesOutAndTheRunGoesOn() {
        let hangs = file("hangs.pdf")
        let fine = file("fine.pdf")
        let start = Date()
        let result = hydrate([hangs, fine], jobs: 1, timeout: 0.3) { path in
            if path == hangs { Thread.sleep(forTimeInterval: 5) } else { fakeDropbox(path) }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(result.empty, [hangs])
        XCTAssertEqual(result.local, [fine])
    }

    // S11
    func testJobsLimitsConcurrency() {
        for jobs in [1, 3] {
            let files = (0..<9).map { file("j\(jobs)-\($0).pdf") }
            let gauge = ConcurrencyGauge()
            _ = hydrate(files, jobs: jobs, timeout: 10) { path in
                gauge.enter()
                Thread.sleep(forTimeInterval: 0.1)
                fakeDropbox(path)
                gauge.leave()
            }
            let peak = gauge.peak
            XCTAssertLessThanOrEqual(peak, jobs, "jobs=\(jobs)")
            if jobs > 1 { XCTAssertGreaterThan(peak, 1, "jobs=\(jobs) should run in parallel") }
        }
    }

    // S12
    func testUsageErrorsExitTwo() {
        let cases: [[String]] = [
            ["--bogus"], ["--timeout"], ["--jobs"], ["--timeout", "0"], ["--timeout", "abc"],
            ["--jobs", "0"], ["--jobs", "-2"], ["--jobs", "1.5"], [dir + "/does-not-exist"],
        ]
        for args in cases {
            let r = runCLI(args)
            XCTAssertEqual(r.code, 2, "\(args)")
            XCTAssertFalse(r.err.isEmpty, "\(args) must explain on stderr")
        }
    }

    func testParseDefaultsAndValues() throws {
        XCTAssertEqual(try parse([]).paths, ["."])
        let o = try parse(["--dry-run", "--timeout", "2.5", "--jobs", "7", "x", "y"])
        XCTAssertEqual(o.dryRun, true)
        XCTAssertEqual(o.timeout, 2.5)
        XCTAssertEqual(o.jobs, 7)
        XCTAssertEqual(o.paths, ["x", "y"])
        XCTAssertThrowsError(try parse(["--nope"])) {
            XCTAssertEqual($0 as? UsageError, .unknownFlag("--nope"))
        }
        XCTAssertThrowsError(try parse(["--jobs"])) {
            XCTAssertEqual($0 as? UsageError, .missingValue("--jobs"))
        }
    }

    // S13
    func testHelpNamesTheWindowsAndLinuxAlternatives() {
        for flag in ["--help", "-h"] {
            let r = runCLI([flag])
            XCTAssertEqual(r.code, 0)
            let text = r.out.joined(separator: "\n")
            XCTAssertTrue(text.contains("attrib +P"), "Windows alternative")
            XCTAssertTrue(text.contains("Linux"), "Linux note")
            XCTAssertTrue(text.contains("--dry-run"))
        }
    }

    // S14
    func testVersion() {
        let r = runCLI(["--version"])
        XCTAssertEqual(r.code, 0)
        XCTAssertEqual(r.out, [HydrateCore.version])
        XCTAssertNotNil(HydrateCore.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression))
        XCTAssertNotEqual(HydrateCore.version, "0.0.0")
    }

    // N1 — the real coordinated read never modifies a normal file and survives a missing one.
    func testCoordinatedReadIsReadOnly() throws {
        let path = file("keep.txt", "original")
        let before = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as! Date
        Thread.sleep(forTimeInterval: 0.05)
        coordinatedRead(path)
        coordinatedRead(dir + "/missing.txt")
        let after = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as! Date
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "original")
        XCTAssertEqual(before, after)
    }

    func testNoPathMeansCurrentDirectory() {
        let a = file("cwd.pdf")
        let old = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(dir)
        defer { FileManager.default.changeCurrentDirectoryPath(old) }
        let r = runCLI(["--dry-run"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains { $0.hasSuffix("cwd.pdf") }, "\(r.out) should list \(a)")
    }
}
