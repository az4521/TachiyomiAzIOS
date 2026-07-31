import CJVMBridge
import Foundation

public enum TachiJVMCompressionError: LocalizedError, Sendable {
    case gzipDecompressionFailed(Int32)

    public var errorDescription: String? {
        switch self {
            case .gzipDecompressionFailed(let status):
                "Unable to decompress the extension store (status \(status))."
        }
    }
}

public enum TachiJVMCompression {
    public static func gunzip(_ data: Data) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let status = data.withUnsafeBytes { input in
            tjr_gzip_decompress(
                input.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                &output,
                &outputSize
            )
        }
        guard status == TJRStatusOK, let output else {
            throw TachiJVMCompressionError.gzipDecompressionFailed(
                status.rawValue
            )
        }
        defer { tjr_buffer_free(output) }
        return Data(bytes: output, count: outputSize)
    }
}
