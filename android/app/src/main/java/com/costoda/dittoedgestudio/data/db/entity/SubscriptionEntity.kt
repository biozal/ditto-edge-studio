package com.costoda.dittoedgestudio.data.db.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "subscriptions",
    foreignKeys = [
        ForeignKey(
            entity = DatabaseConfigEntity::class,
            parentColumns = ["databaseId"],
            childColumns = ["databaseId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["databaseId"])]
)
data class SubscriptionEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "_id") val id: Long = 0,
    @ColumnInfo(name = "databaseId") val databaseId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "query") val query: String
)
