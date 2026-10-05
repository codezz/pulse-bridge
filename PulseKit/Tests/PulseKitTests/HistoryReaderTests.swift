import Foundation
import Testing
@testable import PulseKit

struct ResponseAssemblerTests {
    @Test func joinsRecordsSplitAcrossPackets() {
        let record = bytes("52 07 00 26 03 20 19 29 46 82 00 a2 06 08 00 44 00 00 00 2f 0f 00 00 00 00")
        var assembler = ResponseAssembler(kind: .activity)
        #expect(assembler.append(record.prefix(20)).isEmpty)
        #expect(assembler.append(record.suffix(5) + bytes("52 ff")) == [[UInt8](record)])
        #expect(assembler.endMarkerPending)
        #expect(assembler.packetCount == 2)
    }

    @Test func recordWithIndex255IsNotAnEndMarker() {
        var assembler = ResponseAssembler(kind: .spotHR)
        _ = assembler.append(bytes("55 ff 00 26"))
        #expect(!assembler.endMarkerPending)
    }
}

@MainActor
struct HistoryReaderTests {
    let reader = HistoryReader(timeZone: utc)

    private func channel(_ pages: [HistoryMode: [Data]]) -> FakeChannel {
        FakeChannel { frame in pages[HistoryMode(rawValue: frame[1])!] ?? [] }
    }

    /// A band that answers every "next page" with a full page again (never an end marker) must not
    /// keep the first sync reading forever.
    @Test func stopsAfterThePageLimit() async throws {
        var reader = HistoryReader(timeZone: utc)
        reader.maxPages = 3
        let page = (0..<HistoryReader.packetsPerPage).map { spotHR(minute: $0 % 60) }
        let ch = FakeChannel { _ in page }
        let result = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(ch.sent.count == 3)
        #expect(result.records.count == 3 * HistoryReader.packetsPerPage)
    }

    @Test func readsUntilEndMarker() async throws {
        let ch = channel([.newest: [spotHR(minute: 30) + spotHR(minute: 20) + bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(result.records.map(\.start) == [utcDate(2026, 6, 16, 10, 30), utcDate(2026, 6, 16, 10, 20)])
        #expect(ch.sent == [Command.history(.spotHR, mode: .newest)])
    }

    @Test func stopsAtCursorAndDrainsTheRest() async throws {
        let ch = channel([.newest: [spotHR(minute: 30), spotHR(minute: 20), spotHR(minute: 10), bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: utcDate(2026, 6, 16, 10, 20), over: ch)
        #expect(result.records.map(\.start) == [utcDate(2026, 6, 16, 10, 30)])
        #expect(ch.queue.isEmpty)
        #expect(ch.sent.count == 1)
    }

    @Test func requestsNextPageAfterAFullPage() async throws {
        let firstPage = (10...59).reversed().map { spotHR(minute: $0) }
        #expect(firstPage.count == HistoryReader.packetsPerPage)
        let ch = channel([.newest: firstPage, .next: [spotHR(minute: 9), spotHR(minute: 8), bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(result.records.count == 52)
        #expect(ch.sent == [Command.history(.spotHR, mode: .newest), Command.history(.spotHR, mode: .next)])
    }

    @Test func nextPageGetsTheFullFirstPacketWait() async throws {
        let firstPage = (10...59).reversed().map { spotHR(minute: $0) }
        let ch = channel([.newest: firstPage, .next: [spotHR(minute: 9), bytes("55 ff")]])
        _ = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(ch.firstWaits == [reader.packetTimeout, reader.packetTimeout])
    }

    @Test func fullPageAsksForTheNextOneWithoutWaiting() async throws {
        let firstPage = (10...59).reversed().map { spotHR(minute: $0) }
        let ch = channel([.newest: firstPage, .next: [spotHR(minute: 9), bytes("55 ff")]])
        _ = try await reader.read(.spotHR, newerThan: nil, over: ch)
        let expected: [FakeChannel.Event] = [.send] + Array(repeating: .packet, count: 50) + [.send]
        #expect(Array(ch.events.prefix(52)) == expected)
    }

    @Test func pausesBetweenPacketsGetTheFullWait() async throws {
        // Real band: about 3 s pauses in the middle of a page (log 2026-10-02).
        let ch = channel([.newest: [spotHR(minute: 3), spotHR(minute: 2), bytes("55 ff")]])
        _ = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(ch.waits.filter { $0 != reader.endMarkerGrace }.allSatisfy { $0 == reader.packetTimeout })
    }

    @Test func buttonEventRightAfterEndMarker() async throws {
        // Real band: `16 09 01` arrived just after the HRV end marker (log 2026-10-02 17:50:27).
        let event = bytes("16 09 01 00 00 00 00 00 00 00 00 00 00 00 00 20")
        let ch = channel([.newest: [spotHR(minute: 5) + bytes("55 ff"), event]])
        #expect(try await reader.read(.spotHR, newerThan: nil, over: ch).records.count == 1)
    }

    @Test func leftoverPacketsFromThePreviousCommandAreSkipped() async throws {
        // Captured: a 52 (activity) packet arrived after the 54 command and shifted every record.
        let stray = bytes("52 09 00 26 03 20 19 29 46 82 00 a2 06 08 00 44 00 00 00 2f 0f 00 00 00 00")
        let ch = channel([.newest: [stray, spotHR(minute: 5), stray, bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(result.records.count == 1)
        #expect(result.dropped == 0)
    }

    @Test func silenceAfterNextPageFails() async {
        let firstPage = (10...59).reversed().map { spotHR(minute: $0) }
        await #expect(throws: PulseError.noResponse(0x55)) {
            try await reader.read(.spotHR, newerThan: nil, over: channel([.newest: firstPage]))
        }
    }

    @Test func defaultTimeZoneFollowsThePhone() {
        #expect(HistoryReader().timeZone == TimeZone.autoupdatingCurrent)
    }

    @Test func pageThatGoesSilentWithoutMarkerFails() async {
        // Every final page from the real band ends with `<op> ff`; silence means the stream broke.
        let ch = channel([.newest: [spotHR(minute: 3), spotHR(minute: 2), spotHR(minute: 1)]])
        await #expect(throws: PulseError.noResponse(0x55)) {
            try await reader.read(.spotHR, newerThan: nil, over: ch)
        }
    }

    @Test func emptyHistoryIsNotAnError() async throws {
        let ch = channel([.newest: [bytes("55 ff")]])
        #expect(try await reader.read(.spotHR, newerThan: nil, over: ch).records.isEmpty)
    }

    @Test func silentBandThrows() async {
        await #expect(throws: PulseError.noResponse(0x55)) {
            try await reader.read(.spotHR, newerThan: nil, over: channel([:]))
        }
    }

    @Test func ignoresDeviceEvents() async throws {
        let event = bytes("16 07 01 00 00 00 00 00 00 00 00 00 00 00 00 1e")
        let ch = channel([.newest: [event, spotHR(minute: 5), event, bytes("55 ff")]])
        #expect(try await reader.read(.spotHR, newerThan: nil, over: ch).records.count == 1)
    }

    @Test func countsUnparsableRecords() async throws {
        let broken = bytes("55 01 00 26 1a 16 10 05 00 46")
        let ch = channel([.newest: [spotHR(minute: 6) + broken + bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: nil, over: ch)
        #expect(result.records.count == 1)
        #expect(result.dropped == 1)
    }

    @Test func implausibleDatesDontStopTheRead() async throws {
        // Review finding: a band clock reset (year 2000) stopped reading at that record.
        let reset = bytes("55 01 00 00 01 01 00 00 00 46")
        let ch = channel([.newest: [spotHR(minute: 30), reset, spotHR(minute: 10), bytes("55 ff")]])
        let result = try await reader.read(.spotHR, newerThan: utcDate(2026, 6, 16, 10, 20), over: ch)
        #expect(result.records.map(\.start) == [utcDate(2026, 6, 16, 10, 30)])
        #expect(result.dropped == 1)
    }
}
