package com.readapp.data.repo

import com.readapp.data.ReadRepository
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.ReplaceRuleDao
import com.readapp.data.model.ReplaceRule

class ReplaceRuleRepository(
    private val remoteDataSourceFactory: RemoteDataSourceFactory,
    private val readRepository: ReadRepository,
    private val localDao: ReplaceRuleDao
) {
    private fun createSource(baseUrl: String, publicUrl: String?) =
        remoteDataSourceFactory.createReplaceRuleRemoteDataSource(baseUrl, publicUrl)

    suspend fun fetchReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<ReplaceRule>> {
        val result = createSource(baseUrl, publicUrl).fetchReplaceRules(accessToken)
        result.getOrNull()?.let { rules ->
            localDao.refreshRules(rules)
        }
        return result
    }

    suspend fun getLocalReplaceRules(): List<ReplaceRule> = localDao.getAllRules()

    fun getLocalReplaceRulesFlow() = localDao.getAllRulesFlow()

    suspend fun addReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Unit> {
        val result = createSource(baseUrl, publicUrl).addReplaceRule(accessToken, rule)
        if (result.isSuccess) {
            localDao.insertRules(listOf(rule))
        }
        return result.fold(
            onSuccess = { Result.success(Unit) },
            onFailure = { Result.failure(it) }
        )
    }

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Unit> {
        val result = createSource(baseUrl, publicUrl).deleteReplaceRule(accessToken, rule)
        if (result.isSuccess) {
            localDao.deleteRule(rule)
        }
        return result.fold(
            onSuccess = { Result.success(Unit) },
            onFailure = { Result.failure(it) }
        )
    }

    suspend fun toggleReplaceRule(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        rule: ReplaceRule,
        isEnabled: Boolean
    ): Result<Unit> {
        val result = createSource(baseUrl, publicUrl).toggleReplaceRule(accessToken, rule, isEnabled)
        if (result.isSuccess) {
            localDao.updateRule(rule.copy(isEnabled = isEnabled))
        }
        return result.fold(
            onSuccess = { Result.success(Unit) },
            onFailure = { Result.failure(it) }
        )
    }

    suspend fun saveReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        createSource(baseUrl, publicUrl).saveReplaceRules(accessToken, jsonContent)

}
