import XCTest
@testable import Eh3dCore

/// The trust in the certificate of a server (the pins kept for each server and what is decided about a chain), and the pieces of the live camera: the cutting of the stream into pictures, the wait before asking again and the number of cameras that run.
final class PinAndStreamTests: XCTestCase {
    // a SHA-256 in base64: 44 characters, the last one "="
    private let pinA = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    private let pinB = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    private let pinC = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="
    private let pinD = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
    private let pinE = "EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE="

    private func store() -> (PinStore, MemoryStore) {
        let memory = MemoryStore()
        return (PinStore(memory), memory)
    }

    // ---- the form of a pin

    func testAPinIsFortyFourCharactersOfBase64WithOneEqualsSignAtTheEnd() {
        XCTAssertTrue(PinStore.isWellFormed(pinA))
        XCTAssertTrue(PinStore.isWellFormed("abcdefghijklmnopqrstuvwxyz0123456789+/ABCDE="))
    }

    func testAPinOfAnotherLengthOrWithoutTheEqualsSignIsNotOne() {
        XCTAssertFalse(PinStore.isWellFormed(""))
        XCTAssertFalse(PinStore.isWellFormed(String(pinA.dropLast())))
        XCTAssertFalse(PinStore.isWellFormed(pinA + "A"))
        XCTAssertFalse(PinStore.isWellFormed(String(repeating: "A", count: 44)))
    }

    func testACharacterOutsideBase64MakesItNotAPin() {
        XCTAssertFalse(PinStore.isWellFormed(String(pinA.dropLast(2)) + "-="))
        XCTAssertFalse(PinStore.isWellFormed(String(pinA.dropLast(2)) + " ="))
        XCTAssertFalse(PinStore.isWellFormed(String(pinA.dropLast(2)) + "\u{00E9}="))
    }

    // ---- what is kept

    func testNothingIsKeptForAServerThatWasNeverPinned() {
        let (pins, _) = store()
        XCTAssertEqual(pins.pins(for: "192.168.0.180"), [])
    }

    func testAPinIsKeptAndGivenBack() {
        let (pins, _) = store()
        pins.add(pinA, for: "192.168.0.180")
        XCTAssertEqual(pins.pins(for: "192.168.0.180"), [pinA])
    }

    func testThePinsOfEachServerAreKeptApart() {
        let (pins, _) = store()
        pins.add(pinA, for: "one.example")
        pins.add(pinB, for: "two.example")
        XCTAssertEqual(pins.pins(for: "one.example"), [pinA])
        XCTAssertEqual(pins.pins(for: "two.example"), [pinB])
    }

    func testTheNameOfTheServerIsNotCaseSensitive() {
        let (pins, _) = store()
        pins.add(pinA, for: "Server.Example")
        XCTAssertEqual(pins.pins(for: "server.example"), [pinA])
    }

    func testSpacesAroundAPinAreIgnoredAndAMalformedPinIsNotKept() {
        let (pins, memory) = store()
        pins.add("  \(pinA)\n", for: "h")
        pins.add("not a pin", for: "h")
        pins.add("", for: "h")
        XCTAssertEqual(pins.pins(for: "h"), [pinA])
        XCTAssertEqual(memory.values.count, 1)
    }

    func testTheSamePinTwiceIsKeptOnceAndMovesToTheEnd() {
        let (pins, _) = store()
        pins.add(pinA, for: "h")
        pins.add(pinB, for: "h")
        pins.add(pinA, for: "h")
        XCTAssertEqual(pins.pins(for: "h"), [pinB, pinA])
    }

    func testAServerKeepsAtMostFourPinsAndTheNewestStay() {
        let (pins, _) = store()
        for pin in [pinA, pinB, pinC, pinD, pinE] { pins.add(pin, for: "h") }
        XCTAssertEqual(pins.pins(for: "h"), [pinB, pinC, pinD, pinE])
    }

    func testClearingForgetsOnlyThatServer() {
        let (pins, _) = store()
        pins.add(pinA, for: "one")
        pins.add(pinB, for: "two")
        pins.clear(for: "one")
        XCTAssertEqual(pins.pins(for: "one"), [])
        XCTAssertEqual(pins.pins(for: "two"), [pinB])
    }

    // ---- the decision about a chain

    func testAPinInAChainTheSystemDoesNotTrustCountsOnlyWhenTheChainWasVerifiedToIt() {
        let (pins, _) = store()
        pins.add(pinA, for: "h")
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinB, pinA], systemTrusts: false, verifiedPins: []), .mismatch)
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinB, pinA], systemTrusts: false, verifiedPins: [pinA]), .trusted)
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinB, pinA], systemTrusts: true, verifiedPins: []), .trusted)
    }

    func testAChainWithAKeptPinIsTrustedWhateverTheSystemSays() {
        let (pins, _) = store()
        pins.add(pinA, for: "h")
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinB, pinA], systemTrusts: false), .trusted)
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinA], systemTrusts: true), .trusted)
    }

    func testAnyOfTheKeptPinsIsEnough() {
        let (pins, _) = store()
        pins.add(pinA, for: "h")
        pins.add(pinB, for: "h")
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinC, pinB], systemTrusts: false), .trusted)
    }

    func testAChainWithNoneOfTheKeptPinsIsRefusedEvenIfTheSystemTrustsIt() {
        let (pins, _) = store()
        pins.add(pinA, for: "h")
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinB, pinC], systemTrusts: true), .mismatch)
    }

    func testTheFirstTimeTheSystemTrustsTheChainItsAuthorityIsPinned() {
        let (pins, _) = store()
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinA, pinB, pinC], systemTrusts: true), .firstUse(pin: pinC))
    }

    func testTheFirstTimeALoneServerPinsItsOwnKey() {
        let (pins, _) = store()
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinA], systemTrusts: true), .firstUse(pin: pinA))
    }

    func testAPrivateAuthorityTheSystemDoesNotKnowAsksToPairFirst() {
        let (pins, _) = store()
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinA, pinB], systemTrusts: false), .unknownAuthority(pin: pinB))
        XCTAssertEqual(pins.decide(host: "h", chainPins: [pinA], systemTrusts: false), .unknownAuthority(pin: pinA))
    }

    func testAnEmptyChainIsNeverTrusted() {
        let (pins, _) = store()
        XCTAssertEqual(pins.decide(host: "h", chainPins: [], systemTrusts: true), .mismatch)
        pins.add(pinA, for: "h")
        XCTAssertEqual(pins.decide(host: "h", chainPins: [], systemTrusts: true), .mismatch)
    }

    // ---- the QR code of Studio

    func testAQrWithOnlyAPinHasNoHost() throws {
        let parsed = try XCTUnwrap(PinStore.parseQr("eh3d-pin:\(pinA)"))
        XCTAssertNil(parsed.host)
        XCTAssertEqual(parsed.pin, pinA)
    }

    func testAQrWithAHostAndAPin() throws {
        let parsed = try XCTUnwrap(PinStore.parseQr("  eh3d-pin:cm5.local:\(pinB)\n"))
        XCTAssertEqual(parsed.host, "cm5.local")
        XCTAssertEqual(parsed.pin, pinB)
    }

    func testAHostWithAPortKeepsEverythingBeforeTheLastColon() throws {
        let parsed = try XCTUnwrap(PinStore.parseQr("eh3d-pin:192.168.0.180:18200:\(pinC)"))
        XCTAssertEqual(parsed.host, "192.168.0.180:18200")
        XCTAssertEqual(parsed.pin, pinC)
    }

    func testAnythingElseIsNotAPairingCode() {
        XCTAssertNil(PinStore.parseQr(""))
        XCTAssertNil(PinStore.parseQr("https://example.com"))
        XCTAssertNil(PinStore.parseQr("eh3d-pin:"))
        XCTAssertNil(PinStore.parseQr("eh3d-pin:not-a-pin"))
        XCTAssertNil(PinStore.parseQr("eh3d-pin::\(pinA)"))
        XCTAssertNil(PinStore.parseQr("EH3D-PIN:\(pinA)"))
        XCTAssertNil(PinStore.parseQr("eh3d-pin:host:short="))
    }

    // ---- the pictures of the live camera

    private func jpeg(_ payload: [UInt8]) -> Data { Data([0xFF, 0xD8] + payload + [0xFF, 0xD9]) }

    func testAStreamWithOnePictureGivesOnePicture() {
        var parser = MjpegFrameParser()
        let frame = jpeg([1, 2, 3])
        XCTAssertEqual(parser.feed(frame), [frame])
    }

    func testTheBoundariesAndHeadersBetweenPicturesAreDropped() {
        var parser = MjpegFrameParser()
        let first = jpeg([1]), second = jpeg([2, 2])
        var stream = Data("--frame\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        stream.append(first)
        stream.append(Data("\r\n--frame\r\nContent-Length: 6\r\n\r\n".utf8))
        stream.append(second)
        XCTAssertEqual(parser.feed(stream), [first, second])
    }

    func testAPictureCutInTwoChunksIsGivenWhenItIsComplete() {
        var parser = MjpegFrameParser()
        let frame = jpeg([9, 8, 7, 6])
        XCTAssertEqual(parser.feed(frame.prefix(4)), [])
        XCTAssertEqual(parser.feed(frame.suffix(from: frame.startIndex + 4)), [frame])
    }

    func testAMarkerCutBetweenTwoChunksIsStillFound() {
        var parser = MjpegFrameParser()
        XCTAssertEqual(parser.feed(Data([0x00, 0xFF])), [])
        XCTAssertEqual(parser.feed(Data([0xD8, 0x05, 0xFF])), [])
        XCTAssertEqual(parser.feed(Data([0xD9])), [Data([0xFF, 0xD8, 0x05, 0xFF, 0xD9])])
    }

    func testTwoPicturesInOneChunkAreGivenInOrder() {
        var parser = MjpegFrameParser()
        let a = jpeg([1]), b = jpeg([2]), c = jpeg([3])
        XCTAssertEqual(parser.feed(a + b + c), [a, b, c])
    }

    func testBytesWithoutAStartMarkerGiveNothingAndDoNotGrowTheBuffer() {
        var parser = MjpegFrameParser()
        for _ in 0..<50 { XCTAssertEqual(parser.feed(Data(repeating: 0x41, count: 1_000)), []) }
        let frame = jpeg([7])
        XCTAssertEqual(parser.feed(frame), [frame])
    }

    func testAnEmptyChunkChangesNothing() {
        var parser = MjpegFrameParser()
        XCTAssertEqual(parser.feed(Data()), [])
        let frame = jpeg([4])
        XCTAssertEqual(parser.feed(frame), [frame])
    }

    func testAPictureLargerThanTheLimitIsThrownAwayAndTheNextOneIsStillRead() {
        var parser = MjpegFrameParser()
        let huge = jpeg([UInt8](repeating: 0x11, count: MjpegFrameParser.maxFrameBytes))
        let small = jpeg([5])
        XCTAssertEqual(parser.feed(huge + small), [small])
    }

    func testAPictureThatNeverEndsDoesNotFillTheMemory() {
        var parser = MjpegFrameParser()
        var chunk = Data([0xFF, 0xD8])
        chunk.append(Data(repeating: 0x22, count: 999_998))
        for _ in 0..<6 { XCTAssertEqual(parser.feed(chunk), []) }
        // what piled up beyond the limit was thrown away, so the next complete picture is still given and is not bigger than the limit
        let frames = parser.feed(jpeg([6]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertLessThanOrEqual(frames[0].count, MjpegFrameParser.maxFrameBytes)
        XCTAssertEqual(frames[0].suffix(5), Data([0xFF, 0xD8, 6, 0xFF, 0xD9]))
    }

    func testResetForgetsAPartialPicture() {
        var parser = MjpegFrameParser()
        XCTAssertEqual(parser.feed(Data([0xFF, 0xD8, 1, 2])), [])
        parser.reset()
        XCTAssertEqual(parser.feed(Data([3, 0xFF, 0xD9])), [])
    }

    // ---- the wait before asking for a stream again

    func testTheWaitDoublesFromOneSecondUpToThirty() {
        var backoff = Backoff()
        var waits: [Double] = []
        for _ in 0..<8 { waits.append(backoff.delaySeconds); backoff.failed() }
        XCTAssertEqual(waits, [1, 2, 4, 8, 16, 30, 30, 30])
    }

    func testAPictureThatArrivesStartsTheWaitAgain() {
        var backoff = Backoff()
        backoff.failed(); backoff.failed(); backoff.failed()
        XCTAssertEqual(backoff.delaySeconds, 8)
        backoff.succeeded()
        XCTAssertEqual(backoff, Backoff())
        XCTAssertEqual(backoff.delaySeconds, 1)
    }

    func testTheCountOfFailuresStopsAtTen() {
        var backoff = Backoff()
        for _ in 0..<100 { backoff.failed() }
        XCTAssertEqual(backoff.attempts, 10)
    }

    // ---- the cameras that run

    func testOnlyTheFirstSixVisibleCamerasRun() {
        XCTAssertEqual(CameraGrid.maxLive, 6)
        XCTAssertEqual(CameraGrid.live(visible: ["a", "b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(CameraGrid.live(visible: (1...9).map { "c\($0)" }), ["c1", "c2", "c3", "c4", "c5", "c6"])
        XCTAssertEqual(CameraGrid.live(visible: []), [])
    }
}
