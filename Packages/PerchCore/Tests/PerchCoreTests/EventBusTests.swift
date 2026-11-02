import Foundation
import Testing

@testable import PerchCore

struct EventBusTests {
    private func event(_ title: String) -> PerchEvent {
        PerchEvent(source: "test", kind: .notice(title: title, message: nil))
    }

    @Test func twoSubscribersBothReceive() async {
        let bus = EventBus()
        let a = await bus.subscribe()
        let b = await bus.subscribe()
        let e = event("hello")
        await bus.publish(e)
        var ia = a.makeAsyncIterator()
        var ib = b.makeAsyncIterator()
        #expect(await ia.next() == e)
        #expect(await ib.next() == e)
    }

    @Test func lateSubscriberGetsNothingEarlier() async {
        let bus = EventBus()
        await bus.publish(event("early"))
        let late = await bus.subscribe()
        let later = event("later")
        await bus.publish(later)
        var it = late.makeAsyncIterator()
        #expect(await it.next() == later)
    }

    @Test func subscriberCountDropsAfterCancel() async throws {
        let bus = EventBus()
        let stream = await bus.subscribe()
        let consumer = Task { for await _ in stream {} }
        #expect(await bus.subscriberCount == 1)
        consumer.cancel()
        await consumer.value
        for _ in 0..<100 where await bus.subscriberCount != 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await bus.subscriberCount == 0)
    }
}
