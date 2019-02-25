import Foundation
import BinaryCodable

public class BinaryCookies: BinaryCodable {
    public var pages: [Page]
    public var metadata: Any

    public required init(from decoder: BinaryDecoder) throws {
        var container = decoder.sequentialContainer(maxLength: nil)

        let magic = try container.decode(length: 4)
        guard magic == BinaryCookies.magic else { throw BinaryDecodingError.dataCorrupted(.init(debugDescription: "Missing magic value")) }

        let pageCount = try container.decode(Int32.self).bigEndian
        var pageSizes: [Int32] = []
        for _ in 0..<pageCount {
            pageSizes.append(try container.decode(Int32.self).bigEndian)
        }

        var pages: [Page] = []
        for pageSize in pageSizes {
            var pageContainer = container.nestedContainer(maxLength: Int(pageSize))
            let page = try pageContainer.decode(Page.self)
            pages.append(page)
        }
        self.pages = pages

        // Checksum
        let _ = try container.decode(length: 4)

        let footer = try container.decode(Int64.self).bigEndian
        guard footer == BinaryCookies.footer else { throw BinaryDecodingError.dataCorrupted(.init(debugDescription: "Invalid cookies footer")) }

        // This feels silly but I don't think there's a better way to do it with BinaryCodable yet?
        var plistData = Data()
        while !container.isAtEnd {
            if let byte = try? container.decode(length: 1) {
                plistData.append(byte)
            }
        }

        metadata = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
    }

    public func encode(to encoder: BinaryEncoder) throws {
        var container = encoder.sequentialContainer()

        try container.encode(sequence: BinaryCookies.magic)
        try container.encode(Int32(pages.count).bigEndian)
        for page in pages {
            try container.encode(Int32(page.totalByteCount).bigEndian)
        }

        for page in pages {
            try container.encode(page)
        }

        let checksum: Int32 = try pages.reduce(0) { try $0 + $1.checksum() }
        try container.encode(checksum.bigEndian)

        try container.encode(BinaryCookies.footer.bigEndian)

        let plistData = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
        try container.encode(sequence: plistData)
    }

    private static let magic = Data("cook".utf8)
    private static let footer: Int64 = 0x071720050000004b
}

public class Page: BinaryCodable {
    public var cookies: [Cookie]

    public required init(from decoder: BinaryDecoder) throws {
        var container = decoder.sequentialContainer(maxLength: nil)

        let header = try container.decode(Int32.self).bigEndian
        guard header == Page.header else { throw BinaryDecodingError.dataCorrupted(.init(debugDescription: "Invalid page header")) }

        let cookieCount = try container.decode(Int32.self)
        // BinaryCodable's container can't seek to an offset, so instead of 
        // using these offsets we trust that the cookies aren't padded and 
        // decode them one after another.
        var cookieOffsets: [Int32] = []
        for _ in 0..<cookieCount {
            cookieOffsets.append(try container.decode(Int32.self))
        }

        let footer = try container.decode(Int32.self)
        guard footer == Page.footer else { throw BinaryDecodingError.dataCorrupted(.init(debugDescription: "Invalid page footer")) }

        var cookies: [Cookie] = []
        for _ in 0..<cookieCount {
            let cookieSize = try container.peek(length: 4).withUnsafeBytes { $0.pointee as Int32 }
            var cookieContainer = container.nestedContainer(maxLength: Int(cookieSize))
            let cookie = try cookieContainer.decode(Cookie.self)
            cookies.append(cookie)
        }
        self.cookies = cookies
    }

    public func encode(to encoder: BinaryEncoder) throws {
        var container = encoder.sequentialContainer()

        try container.encode(Page.header.bigEndian)
        try container.encode(Int32(cookies.count))

        for index in 0..<cookies.count {
            let offset = cookiesByteOffset + cookies[0..<index].reduce(0) { $0 + $1.totalByteCount }
            try container.encode(offset)
        }

        try container.encode(Page.footer)

        for cookie in cookies {
            try container.encode(cookie)
        }
    }

    private var cookiesByteOffset: Int32 {
        return Int32(12 + 4 * cookies.count)
    }

    var totalByteCount: Int32 {
        return cookiesByteOffset + cookies.reduce(0) { $0 + $1.totalByteCount }
    }

    func checksum() throws -> Int32 {
        let data = try BinaryDataEncoder().encode(self)
        var checksum: Int32 = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            checksum += Int32(data[index])
        }
        return checksum
    }

    private static let header: Int32 = 0x00000100
    private static let footer: Int32 = 0x00000000
}

public class Cookie: BinaryCodable {
    public var version: Int32
    public var url: String!
    public var port: Int16?
    public var name: String!
    public var path: String!
    public var value: String!
    public var comment: String?
    public var commentURL: String?
    public let flags: Flags
    public let creation: Date
    public let expiration: Date

    public struct Flags: OptionSet, BinaryCodable {
        public let rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        static let isSecure   = Flags(rawValue: 1)
        static let isHTTPOnly = Flags(rawValue: 1 << 2)
        static let unknown1   = Flags(rawValue: 1 << 3)
        static let unknown2   = Flags(rawValue: 1 << 4)
    }

    public required init(from decoder: BinaryDecoder) throws {
        var container = decoder.sequentialContainer(maxLength: nil)

        let size = try container.decode(Int32.self)
        version = try container.decode(Int32.self)
        flags = try container.decode(Flags.self)
        let hasPort = try container.decode(Int32.self)

        let urlOffset = try container.decode(Int32.self)
        let nameOffset = try container.decode(Int32.self)
        let pathOffset = try container.decode(Int32.self)
        let valueOffset = try container.decode(Int32.self)
        let commentOffset = try container.decode(Int32.self)
        let commentURLOffset = try container.decode(Int32.self)

        let expiration = try container.decode(length: 8).withUnsafeBytes { $0.pointee as TimeInterval }
        self.expiration = Date(timeIntervalSinceReferenceDate: expiration)
        let creation = try container.decode(length: 8).withUnsafeBytes { $0.pointee as TimeInterval }
        self.creation = Date(timeIntervalSinceReferenceDate: creation)

        if hasPort > 0 {
            port = try container.decode(Int16.self)
        }

        // url, name, path, and value aren't in a known order, and because
        // BinaryCodable can't seek to an offset, do a little math to figure out
        // the order and trust that they aren't padded.
        let offsets: [Int32] = [urlOffset, nameOffset, pathOffset, valueOffset, commentOffset, commentURLOffset].sorted()
        for (offset, next) in zip(offsets, offsets.dropFirst() + [size]) {
            let length = Int(next - offset)

            if offset == urlOffset {
                let urlData = try container.decode(length: length)
                url = String(data: urlData, encoding: .utf8)!
            }
            else if offset == nameOffset {
                let nameData = try container.decode(length: length)
                name = String(data: nameData, encoding: .utf8)!
            }
            else if offset == pathOffset {
                let pathData = try container.decode(length: length)
                path = String(data: pathData, encoding: .utf8)!
            }
            else if offset == valueOffset {
                let valueData = try container.decode(length: length)
                value = String(data: valueData, encoding: .utf8)!
            }
            else if offset == commentOffset, offset > 0 {
                let commentData = try container.decode(length: length)
                comment = String(data: commentData, encoding: .utf8)!
            }
            else if offset == commentURLOffset, offset > 0 {
                let commentURLData = try container.decode(length: length)
                commentURL = String(data: commentURLData, encoding: .utf8)!
            }
        }
    }

    public func encode(to encoder: BinaryEncoder) throws {
        var container = encoder.sequentialContainer()

        try container.encode(totalByteCount)
        try container.encode(version)
        try container.encode(flags)
        if port != nil {
            try container.encode(Int32(1))
        }
        else {
            try container.encode(Int32(0))
        }

        let commentOffset = fixedByteSize + (port != nil ? 2 : 0)
        let commentURLOffset = commentOffset + Int32(comment?.utf8.count ?? 0)
        let urlOffset = commentURLOffset + Int32(commentURL?.utf8.count ?? 0)
        try container.encode(urlOffset)
        let nameOffset = urlOffset + Int32(url.utf8.count)
        try container.encode(nameOffset)
        let pathOffset = nameOffset + Int32(name.utf8.count)
        try container.encode(pathOffset)
        let valueOffset = pathOffset + Int32(path.utf8.count)
        try container.encode(valueOffset)
        if comment != nil {
            try container.encode(commentOffset)
        }
        else {
            try container.encode(Int32(0))
        }
        if commentURL != nil {
            try container.encode(commentURLOffset)
        }
        else {
            try container.encode(Int32(0))
        }

        let expiration = withUnsafeBytes(of: self.expiration.timeIntervalSinceReferenceDate) { Data($0) }
        try container.encode(sequence: expiration)
        let creation = withUnsafeBytes(of: self.creation.timeIntervalSinceReferenceDate) { Data($0) }
        try container.encode(sequence: creation)

        if let port = port {
            try container.encode(port)
        }
        if let comment = comment {
            try container.encode(comment, encoding: .utf8, terminator: nil)
        }
        if let commentURL = commentURL {
            try container.encode(commentURL, encoding: .utf8, terminator: nil)
        }
        try container.encode(url, encoding: .utf8, terminator: nil)
        try container.encode(name, encoding: .utf8, terminator: nil)
        try container.encode(path, encoding: .utf8, terminator: nil)
        try container.encode(value, encoding: .utf8, terminator: nil)
    }

    private let fixedByteSize: Int32 = 56

    var totalByteCount: Int32 {
        return fixedByteSize + 
               (port != nil ? 2 : 0) +
               Int32(comment?.utf8.count ?? 0) +
               Int32(commentURL?.utf8.count ?? 0) +
               Int32(url.utf8.count) +
               Int32(name.utf8.count) +
               Int32(path.utf8.count) +
               Int32(value.utf8.count)
    }
}
