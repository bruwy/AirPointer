import AppKit
import Testing
@testable import AirPointer

@MainActor
@Suite("Profile mapping behavior")
struct ProfileMappingBehaviorTests {

    @Test func presentationProfileMapsSlideAndMuteIntents() throws {
        let profile = PresentationProfile()

        let next = try #require(shortcut(from: profile.action(for: .nextSlide)))
        #expect(next.keyCode == KeyCode.rightArrow)
        #expect(next.modifiers == [])

        let previous = try #require(shortcut(from: profile.action(for: .previousSlide)))
        #expect(previous.keyCode == KeyCode.leftArrow)
        #expect(previous.modifiers == [])

        let mute = try #require(shortcut(from: profile.action(for: .toggleMute)))
        #expect(mute.keyCode == KeyCode.a)
        #expect(mute.modifiers == [.command, .shift])
    }

    @Test func callProfileOnlyMapsMuteIntent() throws {
        let profile = CallProfile()

        #expect(shortcut(from: profile.action(for: .nextSlide)) == nil)
        #expect(shortcut(from: profile.action(for: .previousSlide)) == nil)

        let mute = try #require(shortcut(from: profile.action(for: .toggleMute)))
        #expect(mute.keyCode == KeyCode.a)
        #expect(mute.modifiers == [.command, .shift])
    }

    @Test func deepworkProfileLeavesDiscreteIntentsUnmapped() {
        let profile = DeepworkProfile()

        for intent in AirIntent.allCases {
            #expect(shortcut(from: profile.action(for: intent)) == nil)
        }
    }

    @Test func dispatcherReportsFalseWhenSelectedProfileHasNoAction() {
        let dispatcher = IntentDispatcher()
        dispatcher.setProfile(kind: .deepwork)

        #expect(dispatcher.handle(intent: .nextSlide) == false)
        #expect(dispatcher.handle(intent: .previousSlide) == false)
        #expect(dispatcher.handle(intent: .toggleMute) == false)
    }

    @Test func dispatcherUsesInjectedPerformerForMappedProfileAction() throws {
        let performer = RecordingSystemActionPerformer()
        let dispatcher = IntentDispatcher(profile: PresentationProfile(), performer: performer)

        #expect(dispatcher.handle(intent: .nextSlide))
        #expect(performer.actions.count == 1)

        let recordedShortcut = try #require(shortcut(from: performer.actions[0]))
        #expect(recordedShortcut.keyCode == KeyCode.rightArrow)
        #expect(recordedShortcut.modifiers == [])
    }
}

private func shortcut(from action: SystemAction?) -> Shortcut? {
    guard case let .shortcut(shortcut)? = action else {
        return nil
    }

    return shortcut
}

private func shortcut(from action: SystemAction) -> Shortcut? {
    guard case let .shortcut(shortcut) = action else {
        return nil
    }

    return shortcut
}

private final class RecordingSystemActionPerformer: SystemActionPerforming {
    private(set) var actions: [SystemAction] = []

    func perform(_ action: SystemAction) -> Bool {
        actions.append(action)
        return true
    }
}
