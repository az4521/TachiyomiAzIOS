import Foundation

public struct ExtensionHostRequest: Codable, Sendable {
    public let operation: String
    public let extensionId: String?
    public let sourceId: String?
    public let jarPath: String?
    public let entryClass: String?
    public let method: String?
    public let argument: String?
    public let query: String?
    public let filterStates: String?
    public let settingKey: String?
    public let settingType: String?
    public let settingValue: String?
    public let mangaURL: String?
    public let mangaTitle: String?
    public let chapterURL: String?
    public let chapterName: String?
    public let imageURL: String?
    public let pageURL: String?
    public let backupPath: String?

    public init(
        operation: String,
        extensionId: String? = nil,
        sourceId: String? = nil,
        jarPath: String? = nil,
        entryClass: String? = nil,
        method: String? = nil,
        argument: String? = nil,
        query: String? = nil,
        filterStates: String? = nil,
        settingKey: String? = nil,
        settingType: String? = nil,
        settingValue: String? = nil,
        mangaURL: String? = nil,
        mangaTitle: String? = nil,
        chapterURL: String? = nil,
        chapterName: String? = nil,
        imageURL: String? = nil,
        pageURL: String? = nil,
        backupPath: String? = nil
    ) {
        self.operation = operation
        self.extensionId = extensionId
        self.sourceId = sourceId
        self.jarPath = jarPath
        self.entryClass = entryClass
        self.method = method
        self.argument = argument
        self.query = query
        self.filterStates = filterStates
        self.settingKey = settingKey
        self.settingType = settingType
        self.settingValue = settingValue
        self.mangaURL = mangaURL
        self.mangaTitle = mangaTitle
        self.chapterURL = chapterURL
        self.chapterName = chapterName
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.backupPath = backupPath
    }
}

public struct ExtensionHostResponse: Codable, Sendable {
    public let success: Bool
    public let result: String?
    public let error: String?
    public let runtime: String?
    public let javaVersion: String?
    public let packageName: String?
    public let name: String?
    public let version: String?
    public let versionCode: String?
    public let entryClass: String?
    public let minimumSdk: String?
    public let targetSdk: String?
    public let nsfw: String?
    public let extensionLibrary: String?
    public let sourceCount: String?
    public let classCount: String?
    public let maximumClassVersion: String?
    public let requiredJavaVersion: String?
    public let runtimeCompatible: String?
}
