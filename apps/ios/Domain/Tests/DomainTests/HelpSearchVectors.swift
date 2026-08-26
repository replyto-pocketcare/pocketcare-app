import Foundation
@testable import Domain

// Wires HelpSearch.swift into FunctionRegistry.
//
// Web's filter lives inside a component's `useMemo` and cannot be imported, so
// these vectors were generated from a transcription of it. Three of them pin
// details that are easy to get wrong: a whitespace-only query returns
// EVERYTHING (web trims this one, unlike the taxonomy search), section TITLES
// are not searched, and a needle may span the space web inserts between a
// question and its answer.

func registerHelpSearchVectors() {
    FunctionRegistry.register(domain: "help-search", fn: "filterHelp") { input in
        let d = input as! [String: Any]
        let sections = (d["sections"] as! [Any]).map { entry -> HelpSection in
            let s = entry as! [String: Any]
            return HelpSection(
                icon: s["icon"] as! String,
                color: s["color"] as! String,
                title: s["title"] as! String,
                items: (s["items"] as! [Any]).map { i -> HelpItem in
                    let it = i as! [String: Any]
                    return HelpItem(it["q"] as! String, it["a"] as! String)
                }
            )
        }
        return filterHelp(sections, query: d["query"] as! String).map { section in
            [
                "title": section.title,
                "items": section.items.map(\.question),
            ] as [String: Any]
        }
    }
}
