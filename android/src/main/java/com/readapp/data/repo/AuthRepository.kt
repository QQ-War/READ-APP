package com.readapp.data.repo

import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.model.LoginResponse

class AuthRepository(
    private val remoteDataSourceFactory: RemoteDataSourceFactory
) {
    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String): Result<LoginResponse> {
        val source = remoteDataSourceFactory.createAuthRemoteDataSource(baseUrl, publicUrl)
        return source.login(username, password)
    }

    suspend fun changePassword(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        oldPass: String,
        newPass: String
    ): Result<String> {
        val source = remoteDataSourceFactory.createAuthRemoteDataSource(baseUrl, publicUrl)
        return source.changePassword(accessToken, oldPass, newPass)
    }
}
