//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import Foundation
import NukeUI
import SwiftUI

struct SourceImageView: View {
    var source: AidokuRunner.Source?
    var sourceKey: String?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"

    @State private var imageRequest: ImageRequest?

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                GIFImage(
                    data: data,
                    contentMode: contentMode
                )
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            } else {
                let result = if let image = state.image {
                    image
                } else {
                    Image(placeholder)
                }
                result
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            }
        }
        .processors({
            if let downsampleWidth {
                [DownsampleProcessor(width: downsampleWidth)]
            } else {
                []
            }
        }())
        .task(id: ImageRequestIdentity(
            imageUrl: imageUrl,
            sourceKey: source?.key ?? sourceKey
        )) {
            imageRequest = nil
            await loadImageRequest(url: imageUrl)
        }
    }

    func loadImageRequest(url: String) async {
        let url = URL(string: url)
        if let fileUrl = url?.toAidokuFileUrl() {
            imageRequest = ImageRequest(url: fileUrl)
            return
        }
        guard let url, !url.isFileURL else {
            imageRequest = ImageRequest(url: url)
            return
        }

        var resolvedSource = source
        if resolvedSource == nil, let sourceKey {
            await SourceManager.shared.waitForSourcesLoad()
            resolvedSource = SourceManager.shared.source(for: sourceKey)
        }
        guard !Task.isCancelled else { return }

        let urlRequest = if let resolvedSource {
            await resolvedSource.getModifiedImageRequest(url: url, context: nil)
        } else {
            await AidokuRunner.Source.modify(url: url, request: URLRequest(url: url))
        }
        guard !Task.isCancelled else { return }
        imageRequest = ImageRequest(urlRequest: urlRequest)
    }
}

private struct ImageRequestIdentity: Equatable {
    let imageUrl: String
    let sourceKey: String?
}
