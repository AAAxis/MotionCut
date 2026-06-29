import AppIntents
import Foundation

#if os(iOS)
import UIKit
#endif

struct OpenCreatorAIEditorIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CreatorAI Editor"
    static var description = IntentDescription("Open the CreatorAI video editor.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await CreatorAIIntentRouter.openEditor()
        return .result(dialog: "Opening CreatorAI editor.")
    }
}

struct EditCreatorAITimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Edit CreatorAI Timeline"
    static var description = IntentDescription("Open CreatorAI and pass an AI edit instruction to the video editor.")
    static var openAppWhenRun = true

    @Parameter(title: "Instruction", description: "The timeline edit to apply, such as cut boring parts, add captions, or sync clips to music.")
    var instruction: String

    static var parameterSummary: some ParameterSummary {
        Summary("Edit CreatorAI timeline: \(\.$instruction)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await CreatorAIIntentRouter.openEditor(aiInstruction: instruction)
        return .result(dialog: "Opening CreatorAI with your edit instruction.")
    }
}

struct SkipCreatorAICurrentSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Current CreatorAI Scene"
    static var description = IntentDescription("Ask CreatorAI to remove or skip the current scene in the editor.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await CreatorAIIntentRouter.openEditor(aiInstruction: "__creatorai_skip_current_scene")
        return .result(dialog: "Skipping the current CreatorAI scene.")
    }
}

struct CutCreatorAICurrentClipIntent: AppIntent {
    static var title: LocalizedStringResource = "Cut Current CreatorAI Clip"
    static var description = IntentDescription("Ask CreatorAI to cut the current clip at the playhead.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await CreatorAIIntentRouter.openEditor(aiInstruction: "__creatorai_cut_current_clip")
        return .result(dialog: "Cutting the current CreatorAI clip.")
    }
}

struct RemoveCreatorAIBadTakesIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove CreatorAI Bad Takes"
    static var description = IntentDescription("Ask CreatorAI to remove weak, boring, failed, or bad takes from the timeline.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await CreatorAIIntentRouter.openEditor(aiInstruction: "Remove bad takes and boring parts from the current timeline.")
        return .result(dialog: "Removing bad takes in CreatorAI.")
    }
}

struct CreatorAIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCreatorAIEditorIntent(),
            phrases: [
                "Open \(.applicationName) editor",
                "Start editing in \(.applicationName)"
            ],
            shortTitle: "Open Editor",
            systemImageName: "timeline.selection"
        )

        AppShortcut(
            intent: EditCreatorAITimelineIntent(),
            phrases: [
                "Edit my video in \(.applicationName)",
                "Ask \(.applicationName) to edit my timeline"
            ],
            shortTitle: "AI Edit",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: SkipCreatorAICurrentSceneIntent(),
            phrases: [
                "Skip this in \(.applicationName)",
                "Skip current scene in \(.applicationName)",
                "Remove this scene in \(.applicationName)",
                "Use \(.applicationName) to skip this",
                "In \(.applicationName), skip this"
            ],
            shortTitle: "Skip Scene",
            systemImageName: "forward.end.fill"
        )

        AppShortcut(
            intent: CutCreatorAICurrentClipIntent(),
            phrases: [
                "Cut this clip in \(.applicationName)",
                "Cut current clip in \(.applicationName)",
                "Split this in \(.applicationName)",
                "Use \(.applicationName) to cut this clip",
                "In \(.applicationName), split this"
            ],
            shortTitle: "Cut Clip",
            systemImageName: "scissors"
        )

        AppShortcut(
            intent: RemoveCreatorAIBadTakesIntent(),
            phrases: [
                "Remove bad takes in \(.applicationName)",
                "Clean up my timeline in \(.applicationName)",
                "Remove boring parts in \(.applicationName)"
            ],
            shortTitle: "Bad Takes",
            systemImageName: "wand.and.stars"
        )
    }
}

private enum CreatorAIIntentRouter {
    @MainActor
    static func openEditor(aiInstruction: String? = nil) async {
        var components = URLComponents()
        components.scheme = "creatorai"
        components.host = "editor"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Editor")
        ]

        let cleanedInstruction = aiInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanedInstruction, !cleanedInstruction.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "instruction", value: cleanedInstruction))
        }

        guard let url = components.url else { return }

        #if os(iOS)
        await UIApplication.shared.open(url)
        #endif
    }
}
