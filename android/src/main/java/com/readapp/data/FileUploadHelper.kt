package com.readapp.data

import android.content.Context
import android.net.Uri
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody

object FileUploadHelper {
    fun createMultipartBodyPart(
        uri: Uri,
        context: Context,
        fieldName: String = "file"
    ): MultipartBody.Part? {
        return context.contentResolver.openInputStream(uri)?.use { inputStream ->
            val fileBytes = inputStream.readBytes()
            val requestFile = fileBytes.toRequestBody(
                context.contentResolver.getType(uri)?.toMediaTypeOrNull()
            )
            MultipartBody.Part.createFormData(
                fieldName,
                getFileName(uri, context),
                requestFile
            )
        }
    }

    private fun getFileName(uri: Uri, context: Context): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            try {
                if (cursor != null && cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (columnIndex >= 0) {
                        result = cursor.getString(columnIndex)
                    }
                }
            } finally {
                cursor?.close()
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/')
            if (cut != -1) {
                result = result?.substring(cut + 1)
            }
        }
        return result
    }
}
