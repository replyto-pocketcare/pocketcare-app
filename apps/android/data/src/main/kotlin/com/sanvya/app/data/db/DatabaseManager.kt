package com.sanvya.app.data.db

import android.content.Context
import com.powersync.DatabaseDriverFactory
import com.powersync.PowerSyncDatabase
import com.powersync.db.schema.Column
import com.powersync.db.schema.Index
import com.powersync.db.schema.IndexedColumn
import com.powersync.db.schema.Schema
import com.powersync.db.schema.Table
import com.sanvya.app.domain.db.ColumnType
import com.sanvya.app.domain.db.PocketCareSchema

object DatabaseManager {
    fun createDatabase(context: Context): PowerSyncDatabase {
        val powersyncTables = PocketCareSchema.tables.map { tableDef ->
            Table(
                name = tableDef.name,
                columns = tableDef.columns.map { col ->
                    Column(
                        name = col.name,
                        type = when (col.type) {
                            ColumnType.TEXT -> com.powersync.db.schema.ColumnType.TEXT
                            ColumnType.INTEGER -> com.powersync.db.schema.ColumnType.INTEGER
                            ColumnType.REAL -> com.powersync.db.schema.ColumnType.REAL
                        }
                    )
                },
                indexes = tableDef.indexes.map { idx ->
                    Index(
                        name = idx.name,
                        columns = idx.columns.map { idxCol ->
                            IndexedColumn(
                                column = idxCol.name,
                                ascending = idxCol.ascending
                            )
                        }
                    )
                },
                localOnly = tableDef.localOnly,
                insertOnly = tableDef.insertOnly
            )
        }

        val schema = Schema(tables = powersyncTables)
        val factory = DatabaseDriverFactory(context)
        return PowerSyncDatabase(factory, schema)
    }
}
