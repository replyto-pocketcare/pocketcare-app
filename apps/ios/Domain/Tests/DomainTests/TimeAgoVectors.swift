import Foundation
@testable import Domain

// Wires TimeAgo.swift into FunctionRegistry.
//
// Web's version lives in a page module and reads `Date.now()`, so it cannot be
// imported and called with a fixed clock. These vectors were generated from a
// transcription of it with the clock passed in, and they pin the SHAPE the port
// returns rather than web's English strings — see TimeAgo.swift for why the
// port returns a shape.

func registerTimeAgoVectors() {
    FunctionRegistry.register(domain: "time-ago", fn: "timeAgo") { input in
        let d = input as! [String: Any]
        switch timeAgo(d["iso"] as! String, now: d["now"] as! String) {
        case .justNow: return ["unit": "justNow"] as [String: Any]
        case .minutes(let n): return ["unit": "minutes", "value": n] as [String: Any]
        case .hours(let n): return ["unit": "hours", "value": n] as [String: Any]
        case .days(let n): return ["unit": "days", "value": n] as [String: Any]
        case .on(let iso): return ["unit": "on", "iso": iso] as [String: Any]
        }
    }
}
