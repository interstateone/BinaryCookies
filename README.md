# BinaryCookies

Read and write Apple's .binarycookies files

---

Includes the BinaryCookies library and the `dumpcookies` executable.

Install `dumpcookies` with `brew install interstateone/formulae/dump-cookies` or build from source.

I've tested the BinaryCookies library with real-world .binarycookies files and generated files using the HTTPCookieStorage APIs. It's able to decode and re-encode these files with full fidelity, although there are currently two flags with unknown meanings.

## Reference

- http://www.securitylearn.net/2012/10/27/cookies-binarycookies-reader/
- https://it.toolbox.com/blogs/locutus/understanding-the-safari-cookiesbinarycookies-file-format-010712

Some additional information not found elsewhere:

- The 32 bits after the flags are 0x01000000 (little endian 1) if a port is specified, otherwise they're 0x00000000. The port value will be 2 bytes following the creation date.
- After the 32-bit value offset in each cookie is a 32-bit comment offset and a 32-bit comment URL offset. Most cookies don't have these and so they are both 0x00000000. The comment and comment URL come _before_ the URL, so they have the lowest offset values despite the offsets being listed last.
- The last cookie is followed by a 32-bit checksum in big endian format. This is calculated by adding up every 4th byte in each page.
- Following the checksum is the constant value 0x071720050000004b, then binary plist data which holds an NSHTTPCookieAcceptPolicy value.
