import AppIntents
import Foundation

/// What the app should do once a shortcut has opened it. Read (and cleared)
/// by Dart through `poi/native` → `takeLaunchAction`.
enum LaunchAction {
  static let key = "poi.launchAction"

  static func request(_ action: String) {
    UserDefaults.standard.set(action, forKey: key)
  }

  static func take() -> String? {
    let action = UserDefaults.standard.string(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
    return action
  }
}

struct OpenMachineIntent: AppIntent {
  static let title: LocalizedStringResource = "Open The Machine"
  static let description = IntentDescription("Opens the surveillance feed.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult { .result() }
}

struct TalkToMachineIntent: AppIntent {
  static let title: LocalizedStringResource = "Talk to The Machine"
  static let description = IntentDescription("Opens the feed and a conversation with the Machine.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    LaunchAction.request("talk")
    return .result()
  }
}

struct IssueNumberIntent: AppIntent {
  static let title: LocalizedStringResource = "Get a Number"
  static let description = IntentDescription("Opens the feed and has the Machine give out a number.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    LaunchAction.request("number")
    return .result()
  }
}

/// "Hey Siri, talk to The Machine" and friends, also listed in Shortcuts.
struct MachineShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenMachineIntent(),
      phrases: ["Open \(.applicationName)", "Start \(.applicationName)", "Watch with \(.applicationName)"],
      shortTitle: "Open",
      systemImageName: "eye")
    AppShortcut(
      intent: TalkToMachineIntent(),
      phrases: ["Talk to \(.applicationName)", "Ask \(.applicationName)"],
      shortTitle: "Talk",
      systemImageName: "text.bubble")
    AppShortcut(
      intent: IssueNumberIntent(),
      phrases: ["Get a number from \(.applicationName)", "\(.applicationName), give me a number"],
      shortTitle: "Number",
      systemImageName: "phone.arrow.down.left")
  }
}
