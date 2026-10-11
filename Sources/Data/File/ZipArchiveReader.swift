import Foundation
import ZIPFoundation

/// Shared by backups and spreadsheet import. Entries are validated before any
/// bytes are written, and limits apply to actual decompressed chunks as well.
enum ZipArchiveReader {
    static func read(_ data: Data, maximumExpandedSize: UInt64 = 32 * 1024 * 1024) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        let entries = try validatedEntries(archive, maximumExpandedSize: maximumExpandedSize,
                                           maximumEntrySize: maximumExpandedSize)
        var result: [String: Data] = [:]
        var expanded: UInt64 = 0
        for entry in entries where entry.type == .file {
            var content = Data()
            try extract(entry, archive: archive, expanded: &expanded, maximumExpandedSize: maximumExpandedSize) {
                content.append($0)
            }
            result[entry.path] = content
        }
        return result
    }

    static func extract(_ source: URL, to directory: URL,
                        maximumExpandedSize: UInt64 = 2 * 1024 * 1024 * 1024,
                        maximumEntrySize: UInt64 = 128 * 1024 * 1024) throws -> [String: URL] {
        let archive = try Archive(url: source, accessMode: .read)
        let entries = try validatedEntries(archive, maximumExpandedSize: maximumExpandedSize,
                                           maximumEntrySize: maximumEntrySize)
        var result: [String: URL] = [:]
        var expanded: UInt64 = 0
        for entry in entries where entry.type == .file {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw ValidationError.invalid("无法暂存压缩包内容")
            }
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try extract(entry, archive: archive, expanded: &expanded, maximumExpandedSize: maximumExpandedSize) {
                try handle.write(contentsOf: $0)
            }
            result[entry.path] = destination
        }
        return result
    }

    private static func validatedEntries(_ archive: Archive, maximumExpandedSize: UInt64,
                                          maximumEntrySize: UInt64) throws -> [Entry] {
        var entries: [Entry] = []
        var names: Set<String> = []
        var files: Set<String> = []
        var total: UInt64 = 0
        for entry in archive {
            guard entries.count < 20_000 else { throw ValidationError.invalid("压缩包包含过多文件") }
            let name = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let decoded = name.removingPercentEncoding ?? name
            let components = decoded.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.isEmpty, name.utf8.count <= 4096, !decoded.hasPrefix("/"), !decoded.contains("\\"), !decoded.contains(":"),
                  !decoded.unicodeScalars.contains(where: { $0.value < 32 }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  entry.type != .symlink else {
                throw ValidationError.invalid("压缩包包含不安全的文件路径")
            }
            let canonical = name.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(canonical).inserted else {
                throw ValidationError.invalid("压缩包包含重复文件")
            }
            if entry.type == .file { files.insert(canonical) }
            guard entry.uncompressedSize <= maximumEntrySize,
                  entry.uncompressedSize <= maximumExpandedSize - total else {
                throw ValidationError.invalid("压缩包展开后过大，请拆分后再导入")
            }
            total += entry.uncompressedSize
            entries.append(entry)
        }
        for name in names {
            var parent = name
            while let slash = parent.lastIndex(of: "/") {
                parent = String(parent[..<slash])
                guard !files.contains(parent) else { throw ValidationError.invalid("压缩包文件路径冲突") }
            }
        }
        return entries
    }

    private static func extract(_ entry: Entry, archive: Archive, expanded: inout UInt64,
                                maximumExpandedSize: UInt64, consumer: (Data) throws -> Void) throws {
        var entrySize: UInt64 = 0
        var total = expanded
        let checksum = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
            try Task.checkCancellation()
            let count = UInt64(chunk.count)
            guard count <= entry.uncompressedSize - entrySize, count <= maximumExpandedSize - total else {
                throw ValidationError.invalid("压缩包展开后大小不符或超出限制")
            }
            entrySize += count
            total += count
            try consumer(chunk)
        }
        guard checksum == entry.checksum, entrySize == entry.uncompressedSize else {
            throw ValidationError.invalid("压缩包文件校验失败，请重新导出备份")
        }
        expanded = total
    }
}
