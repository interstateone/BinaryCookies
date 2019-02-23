import Foundation
import BinaryCodable
import BinaryCookies

guard var path = CommandLine.arguments[safe: 1] else {
    print("""
          dumpcookies

          Dumps the contents of an Apple .binarycookies file

          Usage:
          dumpcookies COOKIES_FILE
          """)
    exit(EXIT_FAILURE)
}

do {
    let url = URL(fileURLWithPath: path, relativeTo: nil)
    let data = try Data(contentsOf: url)
    let cookies = try BinaryDataDecoder().decode(BinaryCookies.self, from: data)
    dump(cookies)
}
catch {
    print(String(describing: error))
}
