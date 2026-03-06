package com.costoda.dittoedgestudio.data.db.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "databaseConfigs",
    indices = [Index(value = ["databaseId"], unique = true)]
)
data class DatabaseConfigEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "_id") val id: Long = 0,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "databaseId") val databaseId: String,
    @ColumnInfo(name = "mode") val mode: String,
    @ColumnInfo(name = "allowUntrustedCerts") val allowUntrustedCerts: Boolean,
    @ColumnInfo(name = "isBluetoothLeEnabled") val isBluetoothLeEnabled: Boolean,
    @ColumnInfo(name = "isLanEnabled") val isLanEnabled: Boolean,
    @ColumnInfo(name = "isAwdlEnabled") val isAwdlEnabled: Boolean,
    @ColumnInfo(name = "isCloudSyncEnabled") val isCloudSyncEnabled: Boolean,
    @ColumnInfo(name = "token") val token: String,
    @ColumnInfo(name = "authUrl") val authUrl: String,
    @ColumnInfo(name = "websocketUrl") val websocketUrl: String,
    @ColumnInfo(name = "httpApiUrl") val httpApiUrl: String,
    @ColumnInfo(name = "httpApiKey") val httpApiKey: String,
    @ColumnInfo(name = "secretKey") val secretKey: String,
    @ColumnInfo(name = "logLevel") val logLevel: String,
    @ColumnInfo(name = "isStrictModeEnabled") val isStrictModeEnabled: Boolean = false,
)
