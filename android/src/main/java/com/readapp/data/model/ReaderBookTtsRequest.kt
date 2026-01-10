package com.readapp.data.model

import com.google.gson.annotations.SerializedName

data class ReaderBookTtsRequest(
    @SerializedName("text") val text: String,
    @SerializedName("type") val type: String = "httpTTS",
    @SerializedName("voice") val voice: String,
    @SerializedName("pitch") val pitch: String,
    @SerializedName("rate") val rate: String,
    @SerializedName("accessToken") val accessToken: String,
    @SerializedName("base64") val base64: String = "1"
)
