import Foundation

/// Display name for the folder a session is working in.
/// Linked git worktrees resolve to the main repository, not the worktree folder.
public enum ProjectIdentity {
    public static func name(fromWorkingDirectory directory: String) -> String? {
        let expanded = (directory as NSString).expandingTildeInPath
        guard let path = expanded.nonEmpty else { return nil }
        let worktree = URL(fileURLWithPath: path, isDirectory: true)
        let gitURL = worktree.appendingPathComponent(".git")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return folderName(of: worktree)
        }
        if isDirectory.boolValue {
            return folderName(of: worktree)
        }
        return worktreeName(fromGitFile: gitURL, worktree: worktree)
            ?? folderName(of: worktree)
    }

    private static func worktreeName(fromGitFile gitFile: URL, worktree: URL) -> String? {
        guard let contents = try? String(contentsOf: gitFile, encoding: .utf8),
              let gitDir = gitDir(fromGitFile: contents, worktree: worktree)
        else { return nil }

        let commondirFile = gitDir.appendingPathComponent("commondir")
        if let commonDir = resolvedPath(
            from: (try? String(contentsOf: commondirFile, encoding: .utf8))?.nonEmpty,
            relativeTo: gitDir
        ) {
            return repositoryName(fromCommonGitDir: commonDir)
        }

        return repositoryName(fromWorktreeGitDir: gitDir)
    }

    private static func gitDir(fromGitFile contents: String, worktree: URL) -> URL? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("gitdir:") else { continue }
            let path = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            return resolvedPath(from: path.nonEmpty, relativeTo: worktree)
        }
        return nil
    }

    private static func resolvedPath(from raw: String?, relativeTo base: URL) -> URL? {
        guard let raw else { return nil }
        if (raw as NSString).isAbsolutePath {
            return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: raw, isDirectory: true, relativeTo: base)
            .absoluteURL
            .standardizedFileURL
    }

    private static func repositoryName(fromCommonGitDir commonDir: URL) -> String? {
        let last = commonDir.lastPathComponent
        if last == ".git" {
            return folderName(of: commonDir.deletingLastPathComponent())
        }
        if last.hasSuffix(".git") {
            return String(last.dropLast(4)).nonEmpty
        }
        return last.nonEmpty
    }

    private static func repositoryName(fromWorktreeGitDir gitDir: URL) -> String? {
        let path = gitDir.path
        let marker = "/.git/worktrees/"
        guard let range = path.range(of: marker, options: .backwards) else { return nil }
        return folderName(of: URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true))
    }

    private static func folderName(of url: URL) -> String? {
        url.lastPathComponent.nonEmpty
    }
}
