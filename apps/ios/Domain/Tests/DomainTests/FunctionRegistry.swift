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

    private static var impls: [Key: (Any) throws -> Any] = [:]

    static func register(domain: String, fn: String, impl: @escaping (Any) throws -> Any) {
        impls[Key(domain: domain, fn: fn)] = impl
    }

    static func lookup(domain: String, fn: String) -> ((Any) throws -> Any)? {
        impls[Key(domain: domain, fn: fn)]
    }
}
