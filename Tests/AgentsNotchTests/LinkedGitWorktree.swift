import Foundation

/// On-disk linked worktree that matches git's `.git` file + `commondir` layout.
struct LinkedGitWorktree {
    let root: URL
    let repository: URL
    let worktree: URL

    var repositoryName: String {
        let last = repository.lastPathComponent
        if last.hasSuffix(".git") { return String(last.dropLast(4)) }
        return last
    }

    var worktreeName: String { worktree.lastPathComponent }

    static func make(
        repositoryName: String = "AgentNotch",
        worktreeName: String = "t3code-223a0195",
        worktreeSubpath: String? = nil,
        relativeGitDir: Bool = false,
        bare: Bool = false
    ) throws -> LinkedGitWorktree {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("linked-git-worktree-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent(
            bare ? "\(repositoryName).git" : repositoryName,
            isDirectory: true
        )
        let worktree = root.appendingPathComponent(
            worktreeSubpath ?? "worktrees/\(worktreeName)",
            isDirectory: true
        )
        let gitDir = repository.appendingPathComponent(
            bare ? "worktrees/\(worktreeName)" : ".git/worktrees/\(worktreeName)",
            isDirectory: true
        )

        try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)

        let gitDirValue = relativeGitDir
            ? relativePath(from: worktree, to: gitDir)
            : gitDir.path
        try "gitdir: \(gitDirValue)\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "../..\n".write(
            to: gitDir.appendingPathComponent("commondir"),
            atomically: true,
            encoding: .utf8
        )

        return LinkedGitWorktree(root: root, repository: repository, worktree: worktree)
    }

    private static func relativePath(from origin: URL, to destination: URL) -> String {
        let originParts = origin.standardizedFileURL.pathComponents
        let destinationParts = destination.standardizedFileURL.pathComponents
        var shared = 0
        while shared < originParts.count,
              shared < destinationParts.count,
              originParts[shared] == destinationParts[shared]
        {
            shared += 1
        }
        let ups = Array(repeating: "..", count: originParts.count - shared)
        let downs = Array(destinationParts.dropFirst(shared))
        return (ups + downs).joined(separator: "/")
    }
}
