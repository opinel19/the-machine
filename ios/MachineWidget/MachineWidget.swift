import SwiftUI
import WidgetKit

/// The widget has nothing live to show; one entry that never changes.
struct MachineEntry: TimelineEntry {
  let date: Date
}

struct MachineProvider: TimelineProvider {
  func placeholder(in context: Context) -> MachineEntry { MachineEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (MachineEntry) -> Void) {
    completion(MachineEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MachineEntry>) -> Void) {
    completion(Timeline(entries: [MachineEntry(date: .now)], policy: .never))
  }
}

private let machineYellow = Color(red: 0.933, green: 0.914, blue: 0.235)

/// The Machine's box: corner brackets, dashed edges, a tick mid-edge.
struct MachineBox: View {
  var color: Color = machineYellow
  var lineWidth: CGFloat = 2

  var body: some View {
    GeometryReader { geo in
      let s = min(geo.size.width, geo.size.height)
      let arm = s * 0.2
      ZStack {
        Rectangle()
          .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 0.6, dash: [s * 0.05, s * 0.05]))
        Path { p in
          for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (s, 0.0, -1.0, 1.0), (s, s, -1.0, -1.0), (0.0, s, 1.0, -1.0)] {
            p.move(to: CGPoint(x: x, y: y + dy * arm))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + dx * arm, y: y))
          }
          p.move(to: CGPoint(x: s / 2, y: 0))
          p.addLine(to: CGPoint(x: s / 2, y: s * 0.07))
          p.move(to: CGPoint(x: s / 2, y: s))
          p.addLine(to: CGPoint(x: s / 2, y: s - s * 0.07))
          p.move(to: CGPoint(x: 0, y: s / 2))
          p.addLine(to: CGPoint(x: s * 0.07, y: s / 2))
          p.move(to: CGPoint(x: s, y: s / 2))
          p.addLine(to: CGPoint(x: s - s * 0.07, y: s / 2))
        }
        .stroke(color, lineWidth: lineWidth * 2)
      }
      .frame(width: s, height: s)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct MachineWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: MachineEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        MachineBox(color: .white, lineWidth: 1.2).padding(9)
      }
    case .accessoryRectangular:
      HStack(spacing: 8) {
        MachineBox(color: .white, lineWidth: 1).frame(width: 34, height: 34)
        VStack(alignment: .leading, spacing: 1) {
          Text("THE MACHINE").font(.system(size: 13, weight: .bold, design: .monospaced))
          Text("TAP TO WATCH").font(.system(size: 10, design: .monospaced)).opacity(0.7)
        }
      }
    case .systemMedium:
      HStack(spacing: 14) {
        ZStack(alignment: .topLeading) {
          MachineBox().padding(.top, 14)
          Text("ADMIN")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 4)
            .background(machineYellow)
        }
        .frame(width: 96, height: 110)
        VStack(alignment: .leading, spacing: 6) {
          Text("THE MACHINE").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(machineYellow)
          Text("YOU ARE BEING\nWATCHED.").font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
          Text("● LIVE").font(.system(size: 10, design: .monospaced)).foregroundStyle(.red)
        }
        Spacer(minLength: 0)
      }
    default:
      VStack(alignment: .leading, spacing: 6) {
        ZStack(alignment: .topLeading) {
          MachineBox().padding(.top, 12)
          Text("ADMIN")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 3)
            .background(machineYellow)
        }
        Text("YOU ARE BEING WATCHED.")
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
  }
}

@main
struct MachineWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MachineWidget", provider: MachineProvider()) { entry in
      MachineWidgetView(entry: entry)
        .containerBackground(for: .widget) { Color.black }
    }
    .configurationDisplayName("The Machine")
    .description("Open the surveillance feed in one tap.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
  }
}
