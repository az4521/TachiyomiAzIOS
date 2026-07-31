//
//  AddSourceView.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import AidokuRunner
import SwiftUI

struct AddSourceView: View {
    @State private var showLocalSetup = false
    @State private var showKomgaSetup = false
    @State private var showKavitaSetup = false
    @State private var showKeiyoushiExtensions = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                builtInSources
            }
            .contentMarginsPlease(.top, 4)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("ADD_SOURCE"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    var builtInSources: some View {
        Section(NSLocalizedString("BUILT_IN_SOURCES")) {
            Button {
                showKeiyoushiExtensions = true
            } label: {
                Label("Keiyoushi Extensions", systemImage: "shippingbox.fill")
            }
            .background(
                NavigationLink(
                    "",
                    destination: KeiyoushiExtensionCatalogView(),
                    isActive: $showKeiyoushiExtensions
                )
                .hidden()
            )

            if !SourceManager.shared.sources.contains(where: { $0.key == LocalSourceRunner.sourceKey }) {
                ExternalSourceTableCell(
                    source: .init(
                        sourceId: LocalSourceRunner.sourceKey,
                        name: NSLocalizedString("LOCAL_FILES"),
                        languages: ["multi"],
                        version: 1,
                        contentRating: .safe
                    ),
                    subtitle: NSLocalizedString("LOCAL_FILES_TAGLINE"),
                    onGet: {
                        showLocalSetup = true
                        return true
                    }
                )
                .background(NavigationLink("", destination: LocalSetupView(), isActive: $showLocalSetup).hidden())
            }

            ExternalSourceTableCell(
                source: .init(
                    sourceId: "komga",
                    name: NSLocalizedString("KOMGA"),
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("KOMGA_TAGLINE"),
                onGet: {
                    showKomgaSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: KomgaSetupView(), isActive: $showKomgaSetup).hidden())

            ExternalSourceTableCell(
                source: .init(
                    sourceId: "kavita",
                    name: NSLocalizedString("KAVITA"),
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("KAVITA_TAGLINE"),
                onGet: {
                    showKavitaSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: KavitaSetupView(), isActive: $showKavitaSetup).hidden())

        }
    }

}

private struct KeiyoushiExtensionCatalogView: View {
    @State private var catalog: KeiyoushiJarRepository.Catalog?
    @State private var installedVersions: [String: String] = [:]
    @State private var unhealthyExtensions: Set<String> = []
    @State private var installing: Set<String> = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var extensions: [KeiyoushiJarRepository.Catalog.Extension] {
        guard let catalog else { return [] }
        let supported = catalog.extensionList.extensions.filter(
            \.usesSupportedExtensionLibrary
        )
        guard !searchText.isEmpty else { return supported }
        let query = searchText.localizedLowercase
        return supported.filter {
            $0.name.localizedLowercase.contains(query) ||
                $0.sources.contains {
                    $0.name.localizedLowercase.contains(query)
                }
        }
    }

    var body: some View {
        List {
            if catalog == nil, errorMessage == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if extensions.isEmpty {
                Text(NSLocalizedString("NO_RESULTS"))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(extensions) { entry in
                    HStack(spacing: 12) {
                        AsyncImage(url: entry.resources.iconUrl) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                                .lineLimit(1)
                            Text(
                                "\(entry.extensionLib) • " +
                                    Array(Set(entry.sources.map(\.language)))
                                    .sorted()
                                    .joined(separator: ", ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if entry.isNsfw {
                                Text("NSFW")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()

                        Button(buttonTitle(for: entry)) {
                            install(entry)
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            installing.contains(entry.packageName) ||
                                (
                                    installedVersions[entry.packageName] ==
                                        entry.versionName &&
                                    !unhealthyExtensions.contains(
                                        entry.packageName
                                    )
                                )
                        )
                        .overlay {
                            if installing.contains(entry.packageName) {
                                ProgressView()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Keiyoushi")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: NSLocalizedString("SEARCH")
        )
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .alert(
            "Extension Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func buttonTitle(
        for entry: KeiyoushiJarRepository.Catalog.Extension
    ) -> String {
        guard let installed = installedVersions[entry.packageName] else {
            return "Get"
        }
        if unhealthyExtensions.contains(entry.packageName) {
            return "Repair"
        }
        return installed == entry.versionName
            ? NSLocalizedString("INSTALLED")
            : "Update"
    }

    private func reload() async {
        do {
            async let catalog = KeiyoushiJarRepository.fetchCatalog()
            let manifests = try await JVMSourceRuntime.shared
                .installedManifests()
            let verifiedManifests = try await JVMSourceRuntime.shared
                .verifiedInstalledManifests()
            installedVersions = Dictionary(
                uniqueKeysWithValues: manifests.map { ($0.id, $0.version) }
            )
            unhealthyExtensions = Set(manifests.map(\.id)).subtracting(
                verifiedManifests.map(\.id)
            )
            self.catalog = try await catalog
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func install(
        _ entry: KeiyoushiJarRepository.Catalog.Extension
    ) {
        installing.insert(entry.packageName)
        Task {
            defer {
                installing.remove(entry.packageName)
            }
            do {
                let manifest = try await SourceManager.shared
                    .installKeiyoushiExtension(entry)
                installedVersions[entry.packageName] = manifest.version
                unhealthyExtensions.remove(entry.packageName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
