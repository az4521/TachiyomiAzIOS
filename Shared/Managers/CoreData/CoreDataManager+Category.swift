//
//  CoreDataManager+Category.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/11/22.
//

import CoreData

extension CoreDataManager {
    /// Remove all category objects.
    func clearCategories(context: NSManagedObjectContext? = nil) {
        clear(request: CategoryObject.fetchRequest(), context: context)
    }

    /// Get category object with title.
    func getCategory(title: String, context: NSManagedObjectContext? = nil) -> CategoryObject? {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", title)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get all category objects.
    func getCategories(sorted: Bool = true, groupsOnly: Bool = false, context: NSManagedObjectContext? = nil) -> [CategoryObject] {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        if groupsOnly {
            request.predicate = NSPredicate(format: "group == %@", NSNumber(value: true))
        }
        if sorted {
            request.sortDescriptors = [
                NSSortDescriptor(key: "group", ascending: true), // put filter groups on the bottom, if they're included
                NSSortDescriptor(key: "sort", ascending: true)
            ]
        }
        let objects = try? context.fetch(request)
        return objects ?? []
    }

    /// Get category objects for a library manga.
    func getCategories(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [CategoryObject] {
        let libraryObject = getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)
        return (libraryObject?.categories?.allObjects as? [CategoryObject]) ?? []
    }

    func getCategoryTitles(
        sorted: Bool = true,
        excludeFilterGroups: Bool = true,
        context: NSManagedObjectContext? = nil
    ) -> [String] {
        getCategories(sorted: sorted, context: context)
            .filter { excludeFilterGroups ? !$0.group : true }
            .compactMap { $0.title }
    }

    func getFilterGroups(context: NSManagedObjectContext? = nil) -> [FilterGroup] {
        let decoder = JSONDecoder()
        return CoreDataManager.shared.getCategories(groupsOnly: true, context: context)
            .compactMap { (object: CategoryObject) -> FilterGroup? in
                guard
                    let title = object.title,
                    let data = object.data as? Data,
                    let filters = try? decoder.decode([LibraryFilter].self, from: data)
                else {
                    return nil
                }
                return FilterGroup(title: title, filters: filters)
            }
    }

    /// Check if category exists.
    func hasCategory(title: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", title)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Create a category object.
    @discardableResult
    func createCategory(title: String, group: Bool = false, context: NSManagedObjectContext? = nil) -> CategoryObject {
        let context = context ?? self.context

        let request = CategoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "group == %@", NSNumber(value: group))
        request.sortDescriptors = [NSSortDescriptor(key: "sort", ascending: false)]
        request.fetchLimit = 1
        let lastCategoryIndex = (try? context.fetch(request))?.first?.sort ?? -1

        let categoryObject = CategoryObject(context: context)
        categoryObject.title = title
        categoryObject.sort = lastCategoryIndex + 1
        categoryObject.group = group
        return categoryObject
    }

    /// Removes a category with the given title.
    func removeCategory(title: String, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        if let object = self.getCategory(title: title, context: context) {
            context.delete(object)
        }
        // update sort fields
        let categories = getCategories(sorted: true, context: context)
        for (index, category) in categories.enumerated() where category.sort != index {
            category.sort = Int16(index)
        }
    }

    /// Sets a new title for a category object with the given title.
    func renameCategory(title: String, newTitle: String, context: NSManagedObjectContext? = nil) -> Bool {
        guard
            !hasCategory(title: newTitle, context: context),
            let object = getCategory(title: title, context: context)
        else {
            return false
        }
        object.title = newTitle
        return true
    }

    /// Moves a cateogry to a new position.
    func moveCategory(
        title: String,
        toPosition: Int,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? self.context

        guard let categoryObject = getCategory(title: title, context: context) else {
            return
        }

        let fromPosition = Int(categoryObject.sort)
        var categories = getCategories(sorted: true, context: context)

        // ensure move is valid
        guard
            fromPosition != toPosition,
            fromPosition >= 0, fromPosition < categories.count,
            toPosition >= 0, toPosition < categories.count
        else {
            return
        }

        let movedCategory = categories.remove(at: fromPosition)
        categories.insert(movedCategory, at: toPosition)

        // update sort values to match new order
        for (index, category) in categories.enumerated() where category.sort != index {
            category.sort = Int16(index)
        }
    }

    /// Add categories to library manga.
    func addCategoriesToManga(sourceId: String, mangaId: String, categories: [String], context: NSManagedObjectContext? = nil) {
        guard let libraryObject = getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return }
        for category in categories {
            guard let categoryObject = getCategory(title: category, context: context) else { continue }
            libraryObject.addToCategories(categoryObject)
        }
    }

    func addCategoriesToManga(sourceId: String, mangaId: String, categories: [String]) async {
        await addCategoriesToManga(
            [.init(sourceKey: sourceId, mangaKey: mangaId)],
            categories: categories
        )
    }

    /// Add categories to any number of manga with one fetch and one save.
    func addCategoriesToManga(
        _ identifiers: [MangaIdentifier],
        categories: [String]
    ) async {
        await updateMangaCategories(
            identifiers,
            categories: categories,
            removing: false
        )
    }

    /// Remove categories from library manga.
    func removeCategoriesFromManga(sourceId: String, mangaId: String, categories: [String]) async {
        await removeCategoriesFromManga(
            [.init(sourceKey: sourceId, mangaKey: mangaId)],
            categories: categories
        )
    }

    /// Remove categories from any number of manga with one fetch and one save.
    func removeCategoriesFromManga(
        _ identifiers: [MangaIdentifier],
        categories: [String]
    ) async {
        await updateMangaCategories(
            identifiers,
            categories: categories,
            removing: true
        )
    }

    private func updateMangaCategories(
        _ identifiers: [MangaIdentifier],
        categories: [String],
        removing: Bool
    ) async {
        let selected = Set(identifiers)
        let categoryTitles = Set(categories)
        guard !selected.isEmpty, !categoryTitles.isEmpty else { return }

        await container.performBackgroundTask { context in
            let categoryObjects = self.getCategories(
                sorted: false,
                context: context
            ).filter { category in
                category.title.map(categoryTitles.contains) ?? false
            }
            guard !categoryObjects.isEmpty else { return }

            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga != nil")
            request.relationshipKeyPathsForPrefetching = ["manga", "categories"]
            let libraryObjects = (try? context.fetch(request)) ?? []

            for libraryObject in libraryObjects {
                guard
                    let mangaObject = libraryObject.manga,
                    selected.contains(mangaObject.identifier)
                else {
                    continue
                }
                for categoryObject in categoryObjects {
                    if removing {
                        libraryObject.removeFromCategories(categoryObject)
                    } else {
                        libraryObject.addToCategories(categoryObject)
                    }
                }
            }

            do {
                try context.save()
            } catch {
                context.rollback()
                LogManager.logger.error(
                    "CoreDataManager.updateMangaCategories(batch): " +
                        error.localizedDescription
                )
            }
        }
    }

    func setMangaCategories(sourceId: String, mangaId: String, categories: [String]) async {
        await container.performBackgroundTask { context in
            guard let libraryObject = self.getLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            ) else { return }
            libraryObject.categories = NSSet(array: categories.compactMap {
                self.getCategory(title: $0, context: context)
            })
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setMangaCategories: \(error.localizedDescription)")
            }
        }
    }
}
