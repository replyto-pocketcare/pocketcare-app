import Foundation
@testable import Domain

// Wires TileGrid.swift's packRows() into FunctionRegistry.
//
// These vectors have no web counterpart to be generated FROM -- the browser
// does this in CSS -- so they are the specification rather than a recording of
// one. That makes them the only place the row-packing rules are written down as
// behaviour: no dense back-fill, clamp rather than drop an over-wide tile, and
// one column when a caller asks for zero.

func registerTileGridVectors() {
    FunctionRegistry.register(domain: "dashboard-grid", fn: "packRows") { input in
        let d = input as! [String: Any]
        let items = (d["tiles"] as! [Any]).map { entry -> GridItem in
            let t = entry as! [String: Any]
            return GridItem(
                id: t["id"] as! String,
                columns: (t["columns"] as! NSNumber).intValue
            )
        }
        return packRows(items, columns: (d["columns"] as! NSNumber).intValue)
    }
}
