import Foundation

public struct JVMRuntimeConfiguration: Sendable {
    public let javaHomeURL: URL
    public let frameworksURL: URL
    public let classpathURLs: [URL]
    public let additionalOptions: [String]

    public init(
        javaHomeURL: URL,
        frameworksURL: URL,
        classpathURLs: [URL],
        additionalOptions: [String] = []
    ) {
        self.javaHomeURL = javaHomeURL
        self.frameworksURL = frameworksURL
        self.classpathURLs = classpathURLs
        self.additionalOptions = additionalOptions
    }

    var classpath: String {
        classpathURLs
            .map(\.path)
            .joined(separator: ":")
    }
}
