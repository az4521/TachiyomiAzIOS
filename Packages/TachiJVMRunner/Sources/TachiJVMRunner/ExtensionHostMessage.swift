import Foundation

public struct ExtensionHostRequest: Codable, Sendable {
    public let operation: String
    public let extensionId: String?
    public let jarPath: String?
    public let entryClass: String?
    public let method: String?
    public let argument: String?
    public let backupPath: String?

    public init(
        operation: String,
        extensionId: String? = nil,
        jarPath: String? = nil,
        entryClass: String? = nil,
        method: String? = nil,
        argument: String? = nil,
        backupPath: String? = nil
    ) {
        self.operation = operation
        self.extensionId = extensionId
        self.jarPath = jarPath
        self.entryClass = entryClass
        self.method = method
        self.argument = argument
        self.backupPath = backupPath
    }
}

public struct ExtensionHostResponse: Codable, Sendable {
    public let success: Bool
    public let result: String?
    public let error: String?
    public let runtime: String?
    public let javaVersion: String?
}
