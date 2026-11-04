import CryptoKit
import Foundation
import Testing
@testable import frmr

// F-122-B: film model 1 must render exactly as 1.2.1 did, forever. These
// SHA-256 fingerprints of every stock × print × B&W cube (9³) were taken
// from the 1.2.1 code (commit 0ae0e38) before versioning existed. If one
// fails, the v1 parameters or the shared pipeline changed: old photos would
// change look. Change the v2 set instead.
struct FilmModelV1PinnedTests {
    static let pinned: [String: String] = [
        "cine500T cinema false": "6a6d6e1a21146c780220c676db6318c0f996d8c74646a94dca012155b14000f1",
        "cine500T cinema true": "5fe1cf65129eecfdb528af007d977f99734d8379ad7bc115e93f10359929b459",
        "cine500T lab false": "b2280d3040b137f3d4a149b740e08e6431bb0763dc767d3b2699c6027e210ce9",
        "cine500T lab true": "356ed39ab6f409eb0989c186750e1e8b584e9e71e5a5e6b672d29381c3a6500a",
        "cine500T matte false": "e4b5855263e802574f4a5e4e97e22f5b1b69db4e331f56b4b0f16a1aea5026cf",
        "cine500T matte true": "65511d1a4a5540980e9e26407e8ad531b11e14a1bd6390eb7184735a71f4acd4",
        "cine500T projection false": "5dab01b2a9282e5165f7cf76b7a17012f6e4bd1b4ba443818be23b0957a2ced1",
        "cine500T projection true": "0c03828d1d7172b5eb09375f7a36cc57a82e8349424956cddb14b3b2a5ee90f5",
        "daylight200 cinema false": "86f7789ce6d05c666af7c26a052230c3046bc470ea11689bf9b4821caeacf38c",
        "daylight200 cinema true": "31cf5fcbfda5c809d67f0ee56f4d28a279a8052b6bda4c6e211f7b9d9145757e",
        "daylight200 lab false": "30d5f62339109c1b75a1973d69a63724c342c77f9b45c2126560cd9a8ed6125e",
        "daylight200 lab true": "fed0075105d31084e1165d97a2cfca8db65680e6a5f52c553125ecc43082e161",
        "daylight200 matte false": "1d6aa65254663d334fa8f87b9180cfcbe3c427bd13b2b40936a8474cda25d841",
        "daylight200 matte true": "0f9c3095083887b09b4054cb6cd7d02e5686905609443c8ad5de2d138bb406a8",
        "daylight200 projection false": "200a7de6cf0cca5c97925412670611e9e527c2942adc97fb106f3ce1f22713e6",
        "daylight200 projection true": "7ab94df7941102ef6e4dd72b2df2589151ccbcfe40ce4d0c33e374fdfed3d2e7",
        "mono3200 cinema false": "98c79bcb6927cc2735dcb10b5d24a5bd16a1c11904c4fd33726adbefe203d8d6",
        "mono3200 cinema true": "98c79bcb6927cc2735dcb10b5d24a5bd16a1c11904c4fd33726adbefe203d8d6",
        "mono3200 lab false": "ce63168c9621dd0e94e4aebc7ff3d47587b012b3c176de769e4c0cf38b57db57",
        "mono3200 lab true": "ce63168c9621dd0e94e4aebc7ff3d47587b012b3c176de769e4c0cf38b57db57",
        "mono3200 matte false": "fc20d776ff68ae7bf18b4d0ca2490dd115d2c8bf0bebe862e5ab70d1a9115658",
        "mono3200 matte true": "fc20d776ff68ae7bf18b4d0ca2490dd115d2c8bf0bebe862e5ab70d1a9115658",
        "mono3200 projection false": "2dc925e7534489cac14311c3589ea83d5e96955043509a876bad906121316b2f",
        "mono3200 projection true": "2dc925e7534489cac14311c3589ea83d5e96955043509a876bad906121316b2f",
        "mono400 cinema false": "0db5d7014b5b5cef8fe2fe1886856103ea4ccbeb13da5ee2355be3352b8fca7f",
        "mono400 cinema true": "0db5d7014b5b5cef8fe2fe1886856103ea4ccbeb13da5ee2355be3352b8fca7f",
        "mono400 lab false": "19a6cf20a73d7b3a35f7056a2912875d042b0ba551bf5a5109bf25d1acb448ba",
        "mono400 lab true": "19a6cf20a73d7b3a35f7056a2912875d042b0ba551bf5a5109bf25d1acb448ba",
        "mono400 matte false": "5205ab25e196e38931e623b793fd0316a14a9ef4328070b402125ce9c05cd822",
        "mono400 matte true": "5205ab25e196e38931e623b793fd0316a14a9ef4328070b402125ce9c05cd822",
        "mono400 projection false": "6d1ceb795d731e7c2b4e875b2562dcc72827a46db482bde370805f390d002f8b",
        "mono400 projection true": "6d1ceb795d731e7c2b4e875b2562dcc72827a46db482bde370805f390d002f8b",
        "portrait400 cinema false": "5c3bce4678cf20311b108b2567daf53f5efe61d4252273e294c5943d78cb7864",
        "portrait400 cinema true": "870ef04cf547af362265c44f0e1177753da4eabfa2371c9bc2ecf289a74cbd4e",
        "portrait400 lab false": "4fe25611f21050ac227620deb0e514ddd88dc8d21ea017ffb3486b310a72740b",
        "portrait400 lab true": "f5c05fa7533abba48b36483284a0553671050108a8cc0a5344ed6edea4febdc8",
        "portrait400 matte false": "be6c48efd6d4071de3e217aed137cab63224890fd29c9151b07de5982a63965e",
        "portrait400 matte true": "8d39afae79a791e3572c2d5887e24ecfa014d2cdc38095944392947a0d49baa0",
        "portrait400 projection false": "0333675f3b4e77b712f770f00358743d08d6579cc1e6f7c2eef500be2cb1ced4",
        "portrait400 projection true": "580f920d67e9577a26ae6111c7606bcbd38fe4beca1e0089abfaa8d20c109b9b",
        "slide100 cinema false": "1ae5b280b2e74acfd5c8639e33e9564c1e6b71563005ee829289914bc2d2bd0c",
        "slide100 cinema true": "69c77a66fd349ddd05496bcc1f1dc656338a96526639a6468b56b114ca80a224",
        "slide100 lab false": "443b4a139399c74063a541be0eeb661ae984b4f523ad3d9c7a02af4ed555fbb8",
        "slide100 lab true": "f6a6fccf61f875e520a112915faf0be82c45afc9450f5a2b1372052643b416c7",
        "slide100 matte false": "d146a340cabf0d05318a05fa1ce3125bd836d3bc17d92ed9cee971cbae525eaa",
        "slide100 matte true": "3576dc96487fe5b64f8fb864113c96428216136ff8abb3acdead9594eafab966",
        "slide100 projection false": "7e7931e35bd5e9cab551d4f43237ce46d140a1a27ec7c129b90a1367922e9671",
        "slide100 projection true": "ac2f10e93c33f2bf703784a9fe282380a2ef37d8cb954781bba3c09ce3eff991",
    ]

    @Test func modelOneMatchesTheShippedCubes() {
        var checked = 0
        for stock in StripCustomization.FilmStock.allCases {
            guard let negative = stock.negative(version: 1) else { continue }
            for print in StripCustomization.PrintStock.allCases {
                for mono in [false, true] {
                    let data = FilmLUT.cube(
                        negative: negative, print: print.profile(version: 1),
                        monochrome: mono, parameters: .v1, dimension: 9
                    )
                    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    #expect(hash == Self.pinned["\(stock.rawValue) \(print.rawValue) \(mono)"], "\(stock) \(print) mono=\(mono)")
                    checked += 1
                }
            }
        }
        #expect(checked == Self.pinned.count)
    }
}
