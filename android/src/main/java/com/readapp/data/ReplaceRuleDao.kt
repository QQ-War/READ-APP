package com.readapp.data

import androidx.room.*
import com.readapp.data.model.ReplaceRule
import kotlinx.coroutines.flow.Flow

@Dao
interface ReplaceRuleDao {
    @Query("SELECT * FROM replace_rules ORDER BY ruleOrder ASC")
    fun getAllRulesFlow(): Flow<List<ReplaceRule>>

    @Query("SELECT * FROM replace_rules ORDER BY ruleOrder ASC")
    suspend fun getAllRules(): List<ReplaceRule>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRules(rules: List<ReplaceRule>)

    @Query("DELETE FROM replace_rules")
    suspend fun clearAll()

    @Transaction
    suspend fun refreshRules(rules: List<ReplaceRule>) {
        clearAll()
        insertRules(rules)
    }

    @Update
    suspend fun updateRule(rule: ReplaceRule)

    @Delete
    suspend fun deleteRule(rule: ReplaceRule)
}
