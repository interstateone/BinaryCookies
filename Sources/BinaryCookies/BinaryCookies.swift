import Foundation
import BinaryCodable

public class BinaryCookies: BinaryDecodable {
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

    private static let magic = Data("cook".utf8)
    private static let footer = 0x071720050000004b
}

public class Page: BinaryDecodable {
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

    private static let header = 0x00000100
    private static let footer = 0x00000000
}

public class Cookie: BinaryDecodable {
    public var version: Int32
    public var url: String!
    public var name: String!
    public var path: String!
    public var value: String!
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let creation: Date
    public let expiration: Date

    struct Flags: OptionSet, BinaryDecodable {
        let rawValue: Int32

        static let isSecure = Flags(rawValue: 0b1)
        static let isHTTPOnly = Flags(rawValue: 0b100)
    }

    public required init(from decoder: BinaryDecoder) throws {
        var container = decoder.sequentialContainer(maxLength: nil)

        let size = try container.decode(Int32.self)

        version = try container.decode(Int32.self)

        let flags = try container.decode(Flags.self)
        isSecure = flags.contains(.isSecure)
        isHTTPOnly = flags.contains(.isHTTPOnly)

        let _ = try container.decode(length: 4)

        let urlOffset = try container.decode(Int32.self)
        let nameOffset = try container.decode(Int32.self)
        let pathOffset = try container.decode(Int32.self)
        let valueOffset = try container.decode(Int32.self)

        let footer = try container.decode(Int64.self)
        guard footer == Cookie.footer else { throw BinaryDecodingError.dataCorrupted(.init(debugDescription: "Invalid cookie footer")) }

        let expiration = try container.decode(length: 8).withUnsafeBytes { $0.pointee as TimeInterval }
        self.expiration = Date(timeIntervalSinceReferenceDate: expiration)
        let creation = try container.decode(length: 8).withUnsafeBytes { $0.pointee as TimeInterval }
        self.creation = Date(timeIntervalSinceReferenceDate: creation)

        // url, name, path, and value aren't in a known order, and because
        // BinaryCodable can't seek to an offset, do a little math to figure out
        // the order and trust that they aren't padded.
        let offsets: [Int32] = [urlOffset, nameOffset, pathOffset, valueOffset].sorted()
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
        }
    }

    private static let footer = 0x0000000000000000
}
