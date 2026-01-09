package com.readapp.data.repo

import com.readapp.data.ReadRepository
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.model.ReplaceRule

class ReplaceRuleRepository(
    private val remoteDataSourceFactory: RemoteDataSourceFactory,
    private val readRepository: ReadRepository
) {
    private fun createSource(baseUrl: String, publicUrl: String?) =
        remoteDataSourceFactory.createReplaceRuleRemoteDataSource(baseUrl, publicUrl)

    suspend fun fetchReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String) =
        createSource(baseUrl, publicUrl).fetchReplaceRules(accessToken)

    suspend fun addReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule) =
        createSource(baseUrl, publicUrl).addReplaceRule(accessToken, rule)

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule) =
        createSource(baseUrl, publicUrl).deleteReplaceRule(accessToken, rule)

    suspend fun toggleReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule, isEnabled: Boolean) =
        createSource(baseUrl, publicUrl).toggleReplaceRule(accessToken, rule, isEnabled)

    suspend fun saveReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        createSource(baseUrl, publicUrl).saveReplaceRules(accessToken, jsonContent)

}
