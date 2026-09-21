import Foundation
import zlib

/// 轻量 ZIP 读取：EPUB 常用 store / deflate（raw），无第三方依赖
enum MinimalZip {
    struct Entry: Sendable {
        let name: String
        let data: Data
    }

    static func entries(from url: URL) throws -> [Entry] {
        try entries(from: Data(contentsOf: url))
    }

    static func entries(from data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        var offset = 0
        let count = data.count
        while offset + 30 <= count {
            let sig = readU32(data, offset)
            if sig != 0x04034b50 { break }
            let method = Int(readU16(data, offset + 8))
            let general = Int(readU16(data, offset + 6))
            let compSize: Int
            let uncompSize: Int
            let nameLen = Int(readU16(data, offset + 26))
            let extraLen = Int(readU16(data, offset + 28))
            // data descriptor flag
            let usesDescriptor = (general & 0x08) != 0
            if usesDescriptor {
                // sizes may be zero in local header; still try compressed size if present
                compSize = Int(readU32(data, offset + 18))
                uncompSize = Int(readU32(data, offset + 22))
            } else {
                compSize = Int(readU32(data, offset + 18))
                uncompSize = Int(readU32(data, offset + 22))
            }
            let nameStart = offset + 30
            guard nameStart + nameLen <= count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "unknown"
            let dataStart = nameStart + nameLen + extraLen

            if name.hasSuffix("/") {
                offset = dataStart
                continue
            }

            let payload: Data
            if method == 0 {
                guard dataStart + (compSize > 0 ? compSize : uncompSize) <= count else {
                    throw BookImportError.unzipFailed("条目截断：\(name)")
                }
                let size = compSize > 0 ? compSize : uncompSize
                payload = data.subdata(in: dataStart..<(dataStart + size))
                offset = dataStart + size
            } else if method == 8 {
                guard compSize > 0, dataStart + compSize <= count else {
                    throw BookImportError.unzipFailed("deflate 长度无效：\(name)")
                }
                let compressed = data.subdata(in: dataStart..<(dataStart + compSize))
                payload = try inflateRaw(compressed, expected: uncompSize)
                offset = dataStart + compSize
            } else {
                throw BookImportError.unzipFailed("不支持的压缩方式 \(method)（\(name)）")
            }
            entries.append(Entry(name: name, data: payload))
        }
        if entries.isEmpty {
            throw BookImportError.unzipFailed("未找到 ZIP 条目")
        }
        return entries
    }

    static func extract(entries: [Entry], to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for e in entries {
            let dest = directory.appendingPathComponent(e.name)
            let parent = dest.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try e.data.write(to: dest, options: [.atomic])
        }
    }

    private static func readU16(_ data: Data, _ o: Int) -> UInt16 {
        UInt16(data[o]) | (UInt16(data[o + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(data[o])
            | (UInt32(data[o + 1]) << 8)
            | (UInt32(data[o + 2]) << 16)
            | (UInt32(data[o + 3]) << 24)
    }

    /// ZIP method 8 = raw deflate（windowBits = -15）
    private static func inflateRaw(_ src: Data, expected: Int) throws -> Data {
        if src.isEmpty { return Data() }
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw BookImportError.unzipFailed("inflate 初始化失败 (\(status))")
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunk = 64 * 1024
        var outBuffer = [UInt8](repeating: 0, count: chunk)

        try src.withUnsafeBytes { srcBuf in
            guard let srcBase = srcBuf.bindMemory(to: UInt8.self).baseAddress else {
                throw BookImportError.unzipFailed("inflate 源无效")
            }
            stream.next_in = UnsafeMutablePointer(mutating: srcBase)
            stream.avail_in = uInt(src.count)
            repeat {
                let produced: Int = outBuffer.withUnsafeMutableBufferPointer { buf in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(buf.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return buf.count - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(outBuffer, count: produced)
                }
                if status == Z_STREAM_END { break }
                if status != Z_OK && status != Z_BUF_ERROR {
                    throw BookImportError.unzipFailed("inflate 失败 (\(status))")
                }
            } while status != Z_STREAM_END
        }
        if expected > 0, output.count != expected, abs(output.count - expected) > 0 {
            // 部分 EPUB 的 uncompSize 不可靠，只要有输出即可
        }
        if output.isEmpty {
            throw BookImportError.unzipFailed("inflate 输出为空")
        }
        return output
    }
}
