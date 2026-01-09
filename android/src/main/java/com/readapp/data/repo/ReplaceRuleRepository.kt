package com.readapp.data.repo

import com.readapp.data.ReadRepository
import com.readapp.data.model.ReplaceRule

class ReplaceRuleRepository(private val readRepository: ReadRepository) {
    suspend fun fetchReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String) =
        readRepository.fetchReplaceRules(baseUrl, publicUrl, accessToken)

    suspend fun addReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule) =
        readRepository.addReplaceRule(baseUrl, publicUrl, accessToken, rule)

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, id: String) =
        readRepository.deleteReplaceRule(baseUrl, publicUrl, accessToken, id)

    suspend fun toggleReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, id: String, isEnabled: Boolean) =
        readRepository.toggleReplaceRule(baseUrl, publicUrl, accessToken, id, isEnabled)

    suspend fun saveReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        readRepository.saveReplaceRules(baseUrl, publicUrl, accessToken, jsonContent)
}
