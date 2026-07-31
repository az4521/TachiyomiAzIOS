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

    public static func bundled(
        in bundle: Bundle = .main,
        additionalOptions: [String] = []
    ) throws -> JVMRuntimeConfiguration {
        guard let resourcesURL = bundle.resourceURL else {
            throw JVMRuntimeError.invalidConfiguration(
                "Application resource directory is unavailable"
            )
        }
        let javaHomeURL = resourcesURL.appendingPathComponent(
            "java_bundle",
            isDirectory: true
        )
        let hostURL = resourcesURL.appendingPathComponent(
            "tachiaz-extension-host.jar"
        )
        let mobileShimsURL = resourcesURL.appendingPathComponent(
            "tachiaz-mobile-shims.jar"
        )
        let compatibilityURL = resourcesURL.appendingPathComponent(
            "tachiaz-compat",
            isDirectory: true
        )
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: javaHomeURL.path) else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled java_bundle is missing"
            )
        }
        guard fileManager.fileExists(atPath: hostURL.path) else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled extension host JAR is missing"
            )
        }
        guard fileManager.fileExists(atPath: mobileShimsURL.path) else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled mobile JVM shims are missing"
            )
        }
        guard let frameworksURL = bundle.privateFrameworksURL else {
            throw JVMRuntimeError.invalidConfiguration(
                "Application framework directory is unavailable"
            )
        }

        let compatibilityJars = try fileManager
            .contentsOfDirectory(
                at: compatibilityURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "jar" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !compatibilityJars.isEmpty else {
            throw JVMRuntimeError.invalidConfiguration(
                "Bundled Suwayomi compatibility JARs are missing"
            )
        }
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let jvmHome = applicationSupport.appendingPathComponent(
            "JVMHome",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: jvmHome,
            withIntermediateDirectories: true
        )

        return JVMRuntimeConfiguration(
            javaHomeURL: javaHomeURL,
            frameworksURL: frameworksURL,
            // The host contains iOS-safe replacements for a small number of
            // desktop AndroidCompat classes, so it must win parent-first
            // class loading.
            classpathURLs: [hostURL] + compatibilityJars,
            additionalOptions: [
                "-Xbootclasspath/a:\(mobileShimsURL.path)",
                "-Duser.home=\(jvmHome.path)",
                "-Djava.io.tmpdir=\(FileManager.default.temporaryDirectory.path)"
            ] + additionalOptions
        )
    }
}
