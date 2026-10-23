/// Carries a main-actor value (a callback, most often) through code that runs elsewhere and hops
/// back to the main actor to use it. The box is main-actor isolated, so it is `Sendable` whatever
/// it holds, and only the main actor opens it.
@MainActor
final class MainActorBox<Value> {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
