//
//  ProgressLiveActivityAttributes.swift
//  Aidoku
//
//  This file is compiled into both the app and its WidgetKit extension. Keep
//  the model small and Codable: ActivityKit persists content across process
//  launches and transfers it to the extension independently of the app.
//

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct ProgressLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var completed: Double
        var total: Int

        var fractionCompleted: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, completed / Double(total)))
        }

        var percentage: Int {
            Int((fractionCompleted * 100).rounded())
        }
    }

    /// A stable operation identifier makes each activity easy to inspect and
    /// lets future versions add operation-specific presentation if needed.
    var operationIdentifier: String
}
#endif
