package com.readapp.data.repo

import com.readapp.data.ReadRepository

class AuthRepository(private val readRepository: ReadRepository) {
    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String) =
        readRepository.login(baseUrl, publicUrl, username, password)

    suspend fun changePassword(baseUrl: String, publicUrl: String?, accessToken: String, oldPass: String, newPass: String) =
        readRepository.changePassword(baseUrl, publicUrl, accessToken, oldPass, newPass)
}
