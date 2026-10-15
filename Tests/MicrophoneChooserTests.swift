import CoreAudio
import SwiftUI
import ViewInspector
import XCTest
@testable import AudioWhisper

final class MicrophoneChooserTests: XCTestCase {
    private let builtIn = MicrophoneChooser.Input(uid: "builtin", kind: .builtIn)
    private let usb = MicrophoneChooser.Input(uid: "usb", kind: .external)
    private let headset = MicrophoneChooser.Input(uid: "headset", kind: .external)
    private let loopback = MicrophoneChooser.Input(uid: "loopback", kind: .virtual)

    private func choose(
        _ ranking: [String], connected: [MicrophoneChooser.Input], systemDefault: String? = "builtin",
        lidClosed: Bool = false
    ) -> String {
        MicrophoneChooser(connected: { connected }, defaultUID: { systemDefault }, lidClosed: { lidClosed })
            .choose(ranking: ranking.map { PreferredMicrophone(uid: $0, name: "") })
    }

    func testTheFirstConnectedRankedMicrophoneWins() {
        XCTAssertEqual(choose(["usb", "headset"], connected: [builtIn, headset, usb]), "usb")
        XCTAssertEqual(choose(["usb", "headset"], connected: [builtIn, headset]), "headset")
    }

    func testWithNothingRankedConnectedTheSystemDefaultIsUsed() {
        XCTAssertEqual(choose(["usb"], connected: [builtIn]), "")
        XCTAssertEqual(choose([], connected: [builtIn, usb]), "")
    }

    func testAClosedLidPassesOverARankedBuiltInMicrophone() {
        XCTAssertEqual(choose(["builtin", "usb"], connected: [builtIn, usb], lidClosed: true), "usb")
        XCTAssertEqual(choose(["builtin", "usb"], connected: [builtIn, usb]), "builtin", "the lid is open")
    }

    func testAClosedLidSwapsADefaultBuiltInMicrophoneForARealInput() {
        XCTAssertEqual(choose([], connected: [builtIn, loopback, headset], lidClosed: true), "headset")
    }

    func testAClosedLidLeavesAnyOtherDefaultAlone() {
        XCTAssertEqual(choose([], connected: [builtIn, usb], systemDefault: "usb", lidClosed: true), "")
        XCTAssertEqual(choose([], connected: [builtIn, usb], systemDefault: nil, lidClosed: true), "")
    }

    func testTheBuiltInMicrophoneIsStillUsedWhenNothingElseCanRecord() {
        XCTAssertEqual(choose([], connected: [builtIn], lidClosed: true), "")
        XCTAssertEqual(choose([], connected: [builtIn, loopback], lidClosed: true), "", "a loopback device is not a microphone")
    }

    func testTransportTypesSortIntoKinds() {
        typealias Kind = MicrophoneChooser.Input.Kind
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeUSB), .external)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeBluetooth), .external)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeVirtual), .virtual)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeAggregate), .virtual)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeAutoAggregate), .virtual)
        XCTAssertEqual(Kind(transport: kAudioDeviceTransportTypeUnknown), .external)
    }

    func testTheLidStateIsReadAsABoolean() {
        XCTAssertTrue(Clamshell.isClosed(kCFBooleanTrue))
        XCTAssertFalse(Clamshell.isClosed(kCFBooleanFalse))
        XCTAssertFalse(Clamshell.isClosed(nil), "a Mac without a lid")
        XCTAssertFalse(Clamshell.isClosed("Yes" as CFString))
        // The live read answers either way; which way depends on the Mac.
        _ = Clamshell.isClosed()
    }

    func testRankingSkipsDuplicatesAndMovesWithinBounds() {
        var ranking: [PreferredMicrophone] = []
        ranking.rank(.init(uid: "a", name: "A"))
        ranking.rank(.init(uid: "b", name: "B"))
        ranking.rank(.init(uid: "a", name: "A again"))
        XCTAssertEqual(ranking.map(\.uid), ["a", "b"])
        XCTAssertEqual(ranking.first?.name, "A")

        ranking.move("b", by: -1)
        XCTAssertEqual(ranking.map(\.uid), ["b", "a"])
        ranking.move("b", by: -1)
        ranking.move("a", by: 1)
        ranking.move("missing", by: 1)
        XCTAssertEqual(ranking.map(\.uid), ["b", "a"])
    }
}

final class MicrophoneRankingSettingsTests: IsolatedXCTestCase {
    override func setUp() {
        super.setUp()
        clear()
    }

    override func tearDown() {
        clear()
        super.tearDown()
    }

    func testTheMicrophoneChosenBeforeRankingBecomesTheFirstChoice() {
        XCTAssertEqual(AppDefaults.microphoneRanking, [])
        AppDefaults.selectedMicrophone = "usb"
        XCTAssertEqual(AppDefaults.microphoneRanking, [PreferredMicrophone(uid: "usb", name: "")])
    }

    func testSavingARankingKeepsTheSingleChoiceInStep() {
        AppDefaults.microphoneRanking = [.init(uid: "headset", name: "Headset"), .init(uid: "usb", name: "USB")]
        XCTAssertEqual(AppDefaults.selectedMicrophone, "headset")
        XCTAssertEqual(AppDefaults.microphoneRanking.map(\.name), ["Headset", "USB"])
    }

    func testAnEmptiedRankingStaysEmpty() {
        AppDefaults.selectedMicrophone = "usb"
        AppDefaults.microphoneRanking = []
        XCTAssertEqual(AppDefaults.microphoneRanking, [], "the old choice does not come back")
        XCTAssertEqual(AppDefaults.selectedMicrophone, "")
    }

    func testAnUnreadableRankingIsEmpty() {
        AppDefaults.defaults.set(Data("not json".utf8), forKey: AppDefaults.Key.microphoneRanking.rawValue)
        XCTAssertEqual(AppDefaults.microphoneRanking, [])
    }

    private func clear() {
        AppDefaults.removeValue(for: .microphoneRanking)
        AppDefaults.removeValue(for: .selectedMicrophone)
    }
}

@MainActor
final class RebuildMicrophoneRankingViewTests: XCTestCase {
    private let builtIn = RebuildMicrophoneInputs.Input(id: "builtin", name: "MacBook Pro Microphone")
    private let usb = RebuildMicrophoneInputs.Input(id: "usb", name: "USB microphone")

    func testConnectedMicrophonesShowTheirLiveNameAndOthersAreMarked() {
        typealias View = RebuildMicrophoneRankingView
        XCTAssertEqual(View.label(for: .init(uid: "usb", name: "Old name"), connected: [usb]), "USB microphone")
        XCTAssertEqual(View.label(for: .init(uid: "yeti", name: "Yeti"), connected: [usb]), "Yeti · unavailable")
        XCTAssertEqual(View.label(for: .init(uid: "yeti", name: ""), connected: [usb]), "Saved microphone · unavailable")
    }

    func testAnEmptyListSaysTheSystemDefaultIsUsed() throws {
        _ = try view(Box([]), connected: [builtIn]).inspect().find(text: "System default")
    }

    func testTheListCanBeAddedToReorderedAndTrimmed() throws {
        let ranking = Box([PreferredMicrophone(uid: "yeti", name: "Yeti")])
        try view(ranking, connected: [builtIn, usb]).inspect().find(button: "USB microphone").tap()
        XCTAssertEqual(ranking.value.map(\.uid), ["yeti", "usb"])

        try view(ranking, connected: [usb]).inspect().find(button: "Move down").tap()
        XCTAssertEqual(ranking.value.map(\.uid), ["usb", "yeti"])

        XCTAssertTrue(try view(ranking, connected: [usb]).inspect().find(button: "Move up").isDisabled(),
                      "the first row cannot move up")

        try view(ranking, connected: [usb]).inspect().find(button: "Remove").tap()
        XCTAssertEqual(ranking.value.map(\.uid), ["yeti"])
    }

    private func view(
        _ ranking: Box<[PreferredMicrophone]>, connected: [RebuildMicrophoneInputs.Input]
    ) -> RebuildMicrophoneRankingView {
        RebuildMicrophoneRankingView(
            ranking: Binding(get: { ranking.value }, set: { ranking.value = $0 }), connected: connected)
    }
}

private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
