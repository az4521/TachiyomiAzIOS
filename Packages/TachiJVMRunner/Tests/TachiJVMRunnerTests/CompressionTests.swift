import Foundation
import XCTest
@testable import TachiJVMRunner

final class CompressionTests: XCTestCase {
    func testDecompressesGzipData() throws {
        let compressed = try XCTUnwrap(
            Data(base64Encoded:
                "H4sIAAAAAAAC/wtJTM7IrMzPzXSMUigoyi/JTypNUyhJLS4B" +
                "AAV4nEEZAAAA"
            )
        )
        let result = try TachiJVMCompression.gunzip(compressed)
        XCTAssertEqual(
            String(data: result, encoding: .utf8),
            "TachiyomiAZ protobuf test"
        )
    }
}
