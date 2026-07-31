import Foundation
import Testing
@testable import TachiJVMRunner

@Test
func requestEncodingUsesStableFieldNames() throws {
    let request = ExtensionHostRequest(
        operation: "loadExtension",
        extensionId: "fixture",
        jarPath: "/tmp/fixture.jar",
        entryClass: "fixture.EchoExtension"
    )

    let data = try JSONEncoder().encode(request)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: String]
    )

    #expect(object["operation"] == "loadExtension")
    #expect(object["extensionId"] == "fixture")
    #expect(object["entryClass"] == "fixture.EchoExtension")
}
