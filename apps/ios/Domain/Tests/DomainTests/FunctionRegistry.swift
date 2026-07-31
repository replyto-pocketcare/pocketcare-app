import Foundation

/// fn implementations, empty until each Phase 1 porting task (plan
/// section 5) registers its own. Keyed by (domain, fn) rather than fn
/// alone since the vector JSON's "fn" field is a bare function name
/// (e.g. "convert") that isn't unique across domains -- money.json and
/// finance.json could both have a "convert", and a flat map would let
/// one silently clobber the other. Mirrors the Android side's
/// FunctionRegistry.kt keying for the same reason.
///
/// A porting task un-skips its vectors by calling `register` from its
/// own test file's setup -- this file stays untouched by every Phase 1
/// task.
enum FunctionRegistry {
    private struct Key: Hashable {
        let domain: String
        let fn: String
    }

    // nonisolated(unsafe), not a plain `static var`: Swift 6's strict
    // concurrency checking flags any mutable static property as
    // "nonisolated global shared mutable state" -- a real build error hit
    // on the first `swift test` run against this file. `@MainActor` was
    // the other compiler-suggested fix, but it would force every
    // register()/lookup() call site (every *Vectors.swift adapter, plus
    // VectorRunnerTests.swift's test methods) to become `async`/`await`
    // for a cross-actor hop that serves no purpose here -- every access
    // is already single-threaded and sequential (one XCTest method
    // registers its domain's functions, then immediately calls
    // runDomain() synchronously in the same method body; this test target
    // has no parallel-execution config enabled). nonisolated(unsafe) is
    // Swift's documented escape hatch for exactly this "the compiler can't
    // prove it, but access really is externally synchronized" case --
    // verified via search before use, not the first guess reached for.
    private nonisolated(unsafe) static var impls: [Key: (Any) throws -> Any] = [:]

    static func register(domain: String, fn: String, impl: @escaping (Any) throws -> Any) {
        impls[Key(domain: domain, fn: fn)] = impl
    }

    static func lookup(domain: String, fn: String) -> ((Any) throws -> Any)? {
        impls[Key(domain: domain, fn: fn)]
    }
}
