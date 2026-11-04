import Testing

@testable import PerchPlayer

/// When NativeEngine moves a freshly opened item to its start (resume latency, WP-07).
struct NativeEngineStartSeekTests {
    @Test func noStartNeedsNoSeek() {
        #expect(!NativeEngine.needsStartSeek(openedAtMs: 0, startMs: 0, serverOffset: false))
        #expect(!NativeEngine.needsStartSeek(openedAtMs: 0, startMs: 0, serverOffset: true))
    }

    @Test func directPlayAlwaysSeeks() {
        #expect(NativeEngine.needsStartSeek(openedAtMs: 0, startMs: 5_000, serverOffset: false))
        #expect(NativeEngine.needsStartSeek(openedAtMs: 0, startMs: 120_000, serverOffset: false))
    }

    @Test func transcodeOpenedAtTheOffsetDoesNotSeekBack() {
        // Live: offset 120 s opened at 120.56 s.
        #expect(!NativeEngine.needsStartSeek(openedAtMs: 120_560, startMs: 120_000, serverOffset: true))
        #expect(!NativeEngine.needsStartSeek(openedAtMs: 117_500, startMs: 120_000, serverOffset: true))
    }

    @Test func transcodeOpenedElsewhereSeeks() {
        // The server ignored the offset, or opened too far past the start.
        #expect(NativeEngine.needsStartSeek(openedAtMs: 0, startMs: 120_000, serverOffset: true))
        #expect(NativeEngine.needsStartSeek(openedAtMs: 125_000, startMs: 120_000, serverOffset: true))
        #expect(NativeEngine.needsStartSeek(openedAtMs: 110_000, startMs: 120_000, serverOffset: true))
    }
}
