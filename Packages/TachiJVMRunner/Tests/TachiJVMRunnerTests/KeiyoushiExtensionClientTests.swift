import Foundation
import Testing
@testable import TachiJVMRunner

@Test
func mangaPageDecodesFromExtensionHostPayload() throws {
    let payload = """
    {
      "mangas": [
        {
          "url": "/series/nano-machine",
          "title": "Nano Machine",
          "thumbnailURL": "https://cdn.example/cover.webp",
          "artist": null,
          "author": null,
          "status": 0,
          "description": null,
          "genre": null
        }
      ],
      "hasNextPage": true
    }
    """

    let page = try JSONDecoder().decode(
        KeiyoushiMangaPage.self,
        from: Data(payload.utf8)
    )

    #expect(page.mangas.count == 1)
    #expect(page.mangas[0].title == "Nano Machine")
    #expect(page.hasNextPage)
}

@Test
func sourceFactoryDescriptorsDecodeFromExtensionHostPayload() throws {
    let payload = """
    [
      {
        "id": 2499283573021220255,
        "name": "MangaDex",
        "lang": "en"
      }
    ]
    """

    let sources = try JSONDecoder().decode(
        [KeiyoushiSourceDescriptor].self,
        from: Data(payload.utf8)
    )

    #expect(sources == [
        KeiyoushiSourceDescriptor(
            id: 2499283573021220255,
            name: "MangaDex",
            lang: "en"
        )
    ])
}
