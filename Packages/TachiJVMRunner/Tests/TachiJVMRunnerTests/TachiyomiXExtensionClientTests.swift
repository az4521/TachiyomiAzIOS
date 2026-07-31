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
        TachiyomiXMangaPage.self,
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
        "name": "Example Source",
        "lang": "en",
        "supportsLatest": true,
        "baseURL": "https://example.org"
      }
    ]
    """

    let sources = try JSONDecoder().decode(
        [TachiyomiXSourceDescriptor].self,
        from: Data(payload.utf8)
    )

    #expect(sources == [
        TachiyomiXSourceDescriptor(
            id: 2499283573021220255,
            name: "Example Source",
            lang: "en",
            supportsLatest: true,
            baseURL: "https://example.org"
        )
    ])
}

@Test
func mangaUpdateAndPagesDecodeFromExtensionHostPayloads() throws {
    let updatePayload = """
    {
      "manga": {
        "url": "/manga/example",
        "title": "Example",
        "thumbnailURL": null,
        "artist": null,
        "author": "Author",
        "status": 1,
        "description": "Description",
        "genre": "Action"
      },
      "chapters": [
        {
          "url": "/chapter/1",
          "name": "Chapter 1",
          "chapterNumber": 1.0,
          "scanlator": "Group",
          "dateUpload": 1700000000000
        }
      ]
    }
    """
    let pagesPayload = """
    [
      {
        "index": 0,
        "url": "",
        "imageURL": "https://uploads.example/page-1.jpg",
        "uri": null
      }
    ]
    """

    let update = try JSONDecoder().decode(
        TachiyomiXMangaUpdate.self,
        from: Data(updatePayload.utf8)
    )
    let pages = try JSONDecoder().decode(
        [TachiyomiXPage].self,
        from: Data(pagesPayload.utf8)
    )

    #expect(update.manga.title == "Example")
    #expect(update.chapters[0].chapterNumber == 1)
    #expect(update.chapters[0].dateUpload == 1_700_000_000_000)
    #expect(pages[0].imageURL == "https://uploads.example/page-1.jpg")
}
