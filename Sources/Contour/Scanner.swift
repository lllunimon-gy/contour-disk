import Foundation
import ContourObjC

public final class ScanCancellation {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public struct FileRecord: Codable, Equatable {
    public let path: String
    public let logicalBytes: UInt64
    public let allocatedBytes: UInt64
    public let modifiedAt: Double
    public let identity: String
    /// Only the first path for a hard-linked inode contributes to totals.
    public let countsTowardTotal: Bool
}
public struct ScanIssue: Codable, Equatable { public let path: String; public let reason: String }
public struct DiskSnapshot: Codable {
    public let formatVersion: Int
    public let root: String
    public let startedAt: Date
    public let finishedAt: Date
    public let files: [FileRecord]
    public let issues: [ScanIssue]
    public let cancelled: Bool
    public let skippedLinks: Int
    public var logicalBytes: UInt64 { files.filter(\.countsTowardTotal).reduce(0) { $0 + $1.logicalBytes } }
    public var allocatedBytes: UInt64 { files.filter(\.countsTowardTotal).reduce(0) { $0 + $1.allocatedBytes } }
    public func largestFiles(limit: Int) -> [FileRecord] {
        Array(files.sorted { $0.logicalBytes == $1.logicalBytes ? $0.path < $1.path : $0.logicalBytes > $1.logicalBytes }.prefix(max(0, limit)))
    }
    public var bytesByExtension: [String: UInt64] {
        Dictionary(grouping: files.filter(\.countsTowardTotal), by: {
            let ext = ($0.path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? "(none)" : ext
        }).mapValues { $0.reduce(0) { $0 + $1.logicalBytes } }
    }
    public var bytesByTopDirectory: [String: UInt64] {
        Dictionary(grouping: files.filter(\.countsTowardTotal), by: {
            $0.path.contains("/") ? String($0.path.split(separator: "/")[0]) : "(root)"
        }).mapValues { $0.reduce(0) { $0 + $1.logicalBytes } }
    }
    public func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> DiskSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: data)
        guard value.formatVersion == 1 else { throw ScanError.unsupportedSnapshot }
        guard Set(value.files.map(\.path)).count == value.files.count else { throw ScanError.invalidSnapshot }
        return value
    }
}
public enum ScanError: Error { case notDirectory, cannotEnumerate, differentRoots, incompleteSnapshot, unsupportedSnapshot, invalidSnapshot }
public struct ChangedFile { public let before: FileRecord; public let after: FileRecord }
public struct SnapshotDifference {
    public let added: [FileRecord]
    public let removed: [FileRecord]
    public let changed: [ChangedFile]
    public init(before: DiskSnapshot, after: DiskSnapshot) throws {
        guard before.root == after.root else { throw ScanError.differentRoots }
        guard !before.cancelled, !after.cancelled, before.issues.isEmpty, after.issues.isEmpty else {
            throw ScanError.incompleteSnapshot
        }
        let old = Dictionary(uniqueKeysWithValues: before.files.map { ($0.path, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.files.map { ($0.path, $0) })
        added = after.files.filter { old[$0.path] == nil }
        removed = before.files.filter { new[$0.path] == nil }
        changed = after.files.compactMap { item in
            guard let previous = old[item.path], previous.logicalBytes != item.logicalBytes ||
                previous.allocatedBytes != item.allocatedBytes || previous.modifiedAt != item.modifiedAt ||
                previous.identity != item.identity else { return nil }
            return ChangedFile(before: previous, after: item)
        }
    }
}

public struct DiskScanner {
    public init() {}
    /// Synchronous, off-main API. Progress runs on the caller's queue every 128 entries and at completion.
    public func scan(root: URL, cancellation: ScanCancellation = ScanCancellation(),
                     progress: ((Int) -> Void)? = nil) throws -> DiskSnapshot {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var rootInfo = CTFileInfo()
        guard root.path.withCString({ CTReadFileInfo($0, &rootInfo) }) == 0, rootInfo.isDirectory != 0 else {
            throw ScanError.notDirectory
        }
        let started = Date()
        var issues: [ScanIssue] = []
        var records: [FileRecord] = []
        var identities: Set<String> = []
        var links = 0
        var visited = 0
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [], errorHandler: { url, error in
            issues.append(ScanIssue(path: url.path, reason: error.localizedDescription))
            return !cancellation.isCancelled
        }) else { throw ScanError.cannotEnumerate }
        while !cancellation.isCancelled, let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 128 == 0 { progress?(visited) }
            var info = CTFileInfo()
            let error = url.path.withCString { CTReadFileInfo($0, &info) }
            guard error == 0 else {
                issues.append(ScanIssue(path: url.path, reason: "lstat errno=\(error)")); continue
            }
            if info.isSymbolicLink != 0 { links += 1; enumerator.skipDescendants(); continue }
            guard info.isRegular != 0 else { continue }
            // Defense against an already-replaced ancestor; this isn't an adversarial sandbox API.
            guard url.resolvingSymlinksInPath().path.hasPrefix(prefix) else {
                enumerator.skipDescendants()
                issues.append(ScanIssue(path: url.path, reason: "resolved outside root")); continue
            }
            let identity = "\(info.device):\(info.inode)"
            records.append(FileRecord(path: String(url.path.dropFirst(prefix.count)),
                                      logicalBytes: info.logicalBytes, allocatedBytes: info.allocatedBytes,
                                      modifiedAt: info.modifiedAt, identity: identity,
                                      countsTowardTotal: identities.insert(identity).inserted))
        }
        progress?(visited)
        return DiskSnapshot(formatVersion: 1, root: root.path, startedAt: started, finishedAt: Date(),
                            files: records.sorted { $0.path < $1.path }, issues: issues,
                            cancelled: cancellation.isCancelled, skippedLinks: links)
    }
}
