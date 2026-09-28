import Foundation
import HydrateCore

let code = run(
    Array(CommandLine.arguments.dropFirst()),
    out: { print($0) },
    err: { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) })
exit(code)
