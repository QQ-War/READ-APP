package com.readapp.data.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class ReplaceRule(
    val id: String = "",
    val pattern: String,
    val replacement: String,
    val scope: String?,
    val name: String,
    val order: Int = 0,
    val isEnabled: Boolean = true
) : Parcelable
