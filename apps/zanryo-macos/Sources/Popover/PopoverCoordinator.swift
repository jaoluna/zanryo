import AppKit
import SwiftUI

@MainActor
final class PopoverCoordinator {
    private let store: ZanryoStore
    private let popover: NSPopover

    init(store: ZanryoStore) {
        self.store = store
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 190)
        popover.contentViewController = NSHostingController(
            rootView: PopoverShellView(store: store)
        )
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        Task { await store.refresh() }
    }
}

private struct PopoverShellView: View {
    @ObservedObject var store: ZanryoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ZANRYO")
                    .font(.headline)
                    .tracking(1.2)
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let snapshot = store.snapshot {
                HStack(alignment: .firstTextBaseline) {
                    Text("Weekly Codex")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(snapshot.quota.weekly.remainingPercent.rounded()))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.949, green: 0.714, blue: 0.196))
                }
            } else {
                Text(store.lastError?.message ?? "Loading Codex quota…")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Forecast dashboard coming next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
