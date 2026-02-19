package com.readapp.data.model

import android.os.Parcelable
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName
import kotlinx.parcelize.Parcelize

@Parcelize
@Entity(tableName = "replace_rules")
data class ReplaceRule(
    @PrimaryKey
    val id: String = "",
    val name: String,
    @SerializedName("group", alternate = ["groupname"])
    val groupname: String? = null,
    val pattern: String,
    val replacement: String,
    val scope: String?,
    val scopeTitle: Boolean = false,
    val scopeContent: Boolean = true,
    val excludeScope: String? = null,
    val isEnabled: Boolean = true,
    val isRegex: Boolean = true,
    val timeoutMillisecond: Long = 3000L,
    @SerializedName("order", alternate = ["ruleOrder"])
    val ruleOrder: Int = 0
) : Parcelable
