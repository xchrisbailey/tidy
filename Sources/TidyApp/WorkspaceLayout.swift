import AppKit
import SwiftUI

/// Keeps a scrollable workspace inside the window instead of allowing the table's
/// ideal height to expand its split view into the native title bar.
struct WorkspacePane<Content: View, Activity: View, Composer: View>: View {
  @ViewBuilder let content: () -> Content
  @ViewBuilder let activity: () -> Activity
  @ViewBuilder let composer: () -> Composer

  var body: some View {
    GeometryReader { viewport in
      VStack(spacing: 0) {
        content()
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        activity()
        composer()
      }
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
    }
  }
}

/// Optional integration-test seam: observes this workspace's native bounds without
/// requiring desktop accessibility permission or adding probes to normal builds.
@MainActor
final class WorkspaceGeometry {
  private var regions: [String: NSView] = [:]

  func record(_ name: String, view: NSView) { regions[name] = view }

  func frames(in window: NSWindow) -> [String: NSRect] {
    regions.compactMapValues { view in
      guard view.window === window, view.bounds.height > 0 else { return nil }
      return view.convert(view.bounds, to: nil)
    }
  }
}

struct WorkspaceRegion: View {
  let name: String
  let geometry: WorkspaceGeometry?

  var body: some View {
    if let geometry { Probe(name: name, geometry: geometry) }
  }

  private struct Probe: NSViewRepresentable {
    let name: String
    let geometry: WorkspaceGeometry

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      geometry.record(name, view: view)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) { geometry.record(name, view: view) }
  }
}
