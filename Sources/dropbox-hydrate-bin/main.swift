import Foundation

#if os(macOS)
    import HydrateCore

    let code = run(
        Array(CommandLine.arguments.dropFirst()),
        out: { print($0) },
        err: { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) })
    exit(code)
#else
    FileHandle.standardError.write(
        """
        dropbox-hydrate-bin is macOS only.
          Windows: reading a placeholder downloads it; whole folder: attrib +P "<folder>" /s /d
          Linux:   Dropbox has no online-only files; a 0-byte file is really empty or excluded
                   by selective sync (dropbox exclude list)

        """.data(using: .utf8)!)
    exit(3)
#endif
