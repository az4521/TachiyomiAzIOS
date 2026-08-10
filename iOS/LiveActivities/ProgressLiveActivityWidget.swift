//
//  ProgressLiveActivityWidget.swift
//  AidokuProgressLiveActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ProgressLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProgressLiveActivityAttributes.self) { context in
            ProgressLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.12))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: iconName(for: context.attributes.operationIdentifier))
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.total > 0 {
                        Text("\(context.state.percentage)%")
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        ProgressLiveActivityIndicator(state: context.state)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.attributes.operationIdentifier))
                    .foregroundStyle(.tint)
            } compactTrailing: {
                if context.state.total > 0 {
                    Text("\(context.state.percentage)%")
                        .font(.caption2.monospacedDigit())
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            } minimal: {
                Image(systemName: iconName(for: context.attributes.operationIdentifier))
                    .foregroundStyle(.tint)
            }
            .keylineTint(.tint)
        }
    }

    private func iconName(for operationIdentifier: String) -> String {
        operationIdentifier == "downloads" ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath"
    }
}

@available(iOS 16.1, *)
private struct ProgressLiveActivityLockScreenView: View {
    let state: ProgressLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if state.total > 0 {
                    Text("\(state.percentage)%")
                        .font(.headline.monospacedDigit())
                }
            }
            ProgressLiveActivityIndicator(state: state)
            Text(state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

@available(iOS 16.1, *)
private struct ProgressLiveActivityIndicator: View {
    let state: ProgressLiveActivityAttributes.ContentState

    @ViewBuilder
    var body: some View {
        if state.total > 0 {
            ProgressView(value: state.fractionCompleted)
        } else {
            ProgressView()
        }
    }
}

@main
struct AidokuProgressLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            ProgressLiveActivityWidget()
        }
    }
}
