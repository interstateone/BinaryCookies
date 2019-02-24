# BinaryCookies

Read and write Apple's .binarycookies files

---

Includes the BinaryCookies library and the `dumpcookies` executable.

Install `dumpcookies` with `brew install interstateone/formulae/dump-cookies` or build from source.

## Reference

- http://www.securitylearn.net/2012/10/27/cookies-binarycookies-reader/
- https://it.toolbox.com/blogs/locutus/understanding-the-safari-cookiesbinarycookies-file-format-010712

Some additional information not found elsewhere:

- After the 32-bit value offset in each cookie is a 32-bit comment offset. Most cookies don't have a comment and so this is 0x00000000. The comment itself comes _before_ the URL, so it has the lowest offset value despite the offset being listed last. I haven't seen any cookies with a comment URL yet, but the 32-bits after the comment offset are probably the offset of the comment URL.
- The last cookie is followed by a 32-bit checksum in big endian format. This is calculated by adding up every 4th byte in each page.
- Following the checksum is the constant value 0x071720050000004b, then binary plist data which holds an NSHTTPCookieAcceptPolicy value.
