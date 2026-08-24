import Foundation

/// A parsed golden vector -- mirrors the shape tools/golden-vectors/export.ts
/// writes: either {fn, input, expected} for a normal case, or
/// {fn, input, throws} for a case that should throw. `expected` and the
/// `throwsName`/`throwsMessage` pair are mutually exclusive per vector.
struct Vector {
    let fn: String
    let input: Any
    let expected: Any?
    let throwsName: String?
    let throwsMessage: String?

    init?(json: Any) {
        guard let dict = json as? [String: Any],
              let fn = dict["fn"] as? String,
              let input = dict["input"] else {
            return nil
        }
        self.fn = fn
        self.input = input
        self.expected = dict["expected"]
        if let throwsDict = dict["throws"] as? [String: Any] {
            self.throwsName = throwsDict["name"] as? String
            self.throwsMessage = throwsDict["message"] as? String
        } else {
            self.throwsName = nil
            self.throwsMessage = nil
        }
    }
}


/// Undo JSONSerialization's decimal promotion.
///
/// Foundation parses a high-precision JSON literal like `0.006666666666666667`
/// into an **NSDecimalNumber**, not a double-backed NSNumber. Converting that
/// decimal back with `.doubleValue` goes through base 10 and lands one ULP away
/// from the binary-nearest double — which is what every other platform, and
/// Swift's own arithmetic, produces:
///
///     expected: NSDecimalNumber(0.006666666666666668, bits 0x3f7b4e81b4e81b50)
///     actual:   __NSCFNumber   (0.006666666666666667, bits 0x3f7b4e81b4e81b4f)
///
/// That is a parsing artifact, not a disagreement about the value: the vector
/// JSON round-trips bit-exactly through `Double`, verified independently. So it
/// is fixed here, at the boundary where the artifact is introduced, rather than
/// by loosening the comparison — a golden vector must keep comparing exactly.
///
/// Only values that are actually fractional or exponential are converted.
/// Foundation also promotes integers too large for Int64, and those must keep
/// their decimal representation rather than be flattened into a Double.
private func normalizeDecimals(_ value: Any) -> Any {
    switch value {
    case let decimal as NSDecimalNumber:
        let text = decimal.description
        guard text.contains(".") || text.lowercased().contains("e"), let d = Double(text) else {
            return value
        }
        return NSNumber(value: d)
    case let array as [Any]:
        return array.map(normalizeDecimals)
    case let dict as [String: Any]:
        return dict.mapValues(normalizeDecimals)
    default:
        return value
    }
}

enum VectorFixtures {
    /// The vectors directory at the repo root -- the single fixture
    /// source shared with the Android runner (plan section 3). SwiftPM's
    /// `resources:` declaration can't reference paths outside the
    /// package (verified via search 2026-07-31 before writing this --
    /// SwiftPM validates that target/resource paths stay contained
    /// within the package), so this reads the files directly off disk
    /// instead, located relative to this source file's own on-disk path
    /// via #filePath. Works for both `swift test` and `xcodebuild test`,
    /// which both run against source checked out on disk, never a
    /// distributed binary.
    static var vectorsDirectory: URL {
        var url = URL(fileURLWithPath: #filePath)
        // This file lives at:
        //   apps/ios/Domain/Tests/DomainTests/VectorFixtures.swift
        // Six components up (the filename, then DomainTests, Tests,
        // Domain, ios, apps) reaches the repo root.
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("tools/golden-vectors/vectors")
    }

    static func load(_ domain: String) throws -> [Vector] {
        let fileURL = vectorsDirectory.appendingPathComponent("\(domain).json")
        let data = try Data(contentsOf: fileURL)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let array = raw as? [Any] else {
            throw NSError(
                domain: "VectorFixtures",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(domain).json did not decode to a JSON array (path: \(fileURL.path))"]
            )
        }
        return array.compactMap { Vector(json: normalizeDecimals($0)) }
    }
}
