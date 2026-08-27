import Foundation
@testable import Domain

// Wires parseAppLink into FunctionRegistry.
//
// These vectors are a SPEC, not a capture. There is no web function to run: on
// web the router IS the path, so the "expected" behaviour lives in the `app/`
// directory's shape, in two redirect files, and in the search page's prefill
// effect. Each vector was written against that source — the static table is
// `find apps/web/app -name page.tsx`, the two redirects are `/subscriptions`
// and `/groups`, and the query rules are URLSearchParams' — so a passing run
// proves iOS and Android agree with each other and with what was read off web,
// not that a browser was observed doing it.
//
// The refusals matter as much as the resolutions. `/cashflow` and `/templates`
// are advertised in the assistant persona and do not exist on web; they are
// pinned as null here so that a later "fix" that invents a native destination
// for them fails loudly instead of quietly sending users somewhere web never
// would.

func registerAppLinkVectors() {
    let domain = "applink"

    FunctionRegistry.register(domain: domain, fn: "parseAppLink") { input in
        let d = input as! [String: Any]
        guard let link = parseAppLink(d["href"] as! String) else { return NSNull() }
        var out: [String: Any] = ["screen": link.screen.rawValue]
        // Absent, not null, when the route has no dynamic segment — the fixture
        // is written the way JSON.stringify would emit it.
        if let id = link.id { out["id"] = id }
        out["query"] = link.query as [String: Any]
        return out
    }
}
