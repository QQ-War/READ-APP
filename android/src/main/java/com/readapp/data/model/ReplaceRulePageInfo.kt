package com.readapp.data.model

import android.os.Parcelable
import com.google.gson.annotations.SerializedName
import kotlinx.parcelize.Parcelize

@Parcelize
data class ReplaceRulePageInfo(
    @SerializedName("page")
    val page: Int,
    @SerializedName("md5")
    val md5: String
) : Parcelable
