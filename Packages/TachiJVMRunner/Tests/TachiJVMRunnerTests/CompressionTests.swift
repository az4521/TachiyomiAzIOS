import Foundation
import Testing
@testable import TachiJVMRunner

struct CompressionTests {
    @Test func decompressesGzipData() throws {
        let compressed = try #require(
            Data(
                base64Encoded:
                    "H4sIAAAAAAAC/wtJTM7IrMzPzXSMUigoyi/JTypNUyhJLS4B" +
                    "AAV4nEEZAAAA"
            )
        )
        let result = try TachiJVMCompression.gunzip(compressed)
        #expect(String(data: result, encoding: .utf8) == "TachiyomiAZ protobuf test")
    }
}
