package com.readapp.data

import com.readapp.data.ReaderLoginRequest
import com.readapp.data.ReaderSaveBookProgressRequest
import com.readapp.data.ReaderSetBookSourceRequest
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.RssEditPayload
import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.RssSourcesResponse
import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.UserInfo
import com.readapp.data.model.toPayload
import com.google.gson.Gson
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody

interface AuthRemoteDataSource {
    suspend fun login(username: String, password: String): Result<LoginResponse>
    suspend fun getUserInfo(accessToken: String): Result<UserInfo>
    suspend fun changePassword(accessToken: String, oldPass: String, newPass: String): Result<String>
}

interface BookRemoteDataSource {
    suspend fun fetchBooks(accessToken: String): Result<List<Book>>
    suspend fun fetchChapterList(accessToken: String, bookUrl: String, bookSourceUrl: String?): Result<List<Chapter>>
    suspend fun fetchChapterContent(accessToken: String, bookUrl: String, bookSourceUrl: String?, index: Int, contentType: Int): Result<String>
    suspend fun saveBookProgress(accessToken: String, bookUrl: String, index: Int, pos: Double, title: String?): Result<String>
    suspend fun setBookSource(accessToken: String, bookUrl: String, newUrl: String, bookSourceUrl: String): Result<Book>
    suspend fun searchBook(accessToken: String, keyword: String, bookSourceUrl: String, page: Int): Result<List<Book>>
}

interface TtsRemoteDataSource {
    suspend fun fetchTtsEngines(accessToken: String): Result<List<HttpTTS>>
    suspend fun fetchDefaultTts(accessToken: String): Result<String>
    suspend fun addTts(accessToken: String, tts: HttpTTS): Result<String>
    suspend fun deleteTts(accessToken: String, id: String): Result<String>
    suspend fun saveTtsBatch(accessToken: String, json: String): Result<Any>
}

interface RssRemoteDataSource {
    suspend fun fetchSources(accessToken: String): Result<RssSourcesResponse>
    suspend fun toggleSource(accessToken: String, sourceUrl: String, isEnabled: Boolean): Result<Any>
    suspend fun saveSource(accessToken: String, remoteId: String?, source: RssSourceItem): Result<Any>
    suspend fun deleteSource(accessToken: String, sourceUrl: String): Result<Any>
}

interface ReplaceRuleRemoteDataSource {
    suspend fun fetchReplaceRules(accessToken: String): Result<List<ReplaceRule>>
    suspend fun addReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any>
    suspend fun deleteReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any>
    suspend fun toggleReplaceRule(accessToken: String, rule: ReplaceRule, isEnabled: Boolean): Result<Any>
    suspend fun saveReplaceRules(accessToken: String, jsonContent: String): Result<Any>
}

class RemoteDataSourceFactory(
    apiFactory: (String) -> ReadApiService,
    readerApiFactory: (String) -> ReaderApiService
) {
    private val failoverClient = FailoverClient(apiFactory, readerApiFactory)
    private val gson = Gson()

    fun createAuthRemoteDataSource(baseUrl: String, publicUrl: String?): AuthRemoteDataSource {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> ReadAuthRemoteDataSource(failoverClient, endpoints)
            ApiBackend.Reader -> ReaderAuthRemoteDataSource(failoverClient, endpoints)
        }
    }

    fun createBookRemoteDataSource(baseUrl: String, publicUrl: String?): BookRemoteDataSource {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> ReadBookRemoteDataSource(failoverClient, endpoints)
            ApiBackend.Reader -> ReaderBookRemoteDataSource(failoverClient, endpoints)
        }
    }

    fun createTtsRemoteDataSource(baseUrl: String, publicUrl: String?): TtsRemoteDataSource {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> ReadTtsRemoteDataSource(failoverClient, endpoints)
            ApiBackend.Reader -> ReaderTtsRemoteDataSource()
        }
    }

    fun createRssRemoteDataSource(baseUrl: String, publicUrl: String?): RssRemoteDataSource {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> ReadRssRemoteDataSource(failoverClient, endpoints, gson)
            ApiBackend.Reader -> ReaderRssRemoteDataSource(failoverClient, endpoints)
        }
    }

    fun createReplaceRuleRemoteDataSource(baseUrl: String, publicUrl: String?): ReplaceRuleRemoteDataSource {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> ReadReplaceRuleRemoteDataSource(failoverClient, endpoints)
            ApiBackend.Reader -> ReaderReplaceRuleRemoteDataSource(failoverClient, endpoints)
        }
    }
}

private class ReadAuthRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : AuthRemoteDataSource {
    override suspend fun login(username: String, password: String): Result<LoginResponse> =
        client.runRead(endpoints) { it.login(username, password) }

    override suspend fun getUserInfo(accessToken: String): Result<UserInfo> =
        client.runRead(endpoints) { it.getUserInfo(accessToken) }

    override suspend fun changePassword(accessToken: String, oldPass: String, newPass: String): Result<String> =
        client.runRead(endpoints) { it.changePassword(accessToken, oldPass, newPass) }
}

private class ReaderAuthRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : AuthRemoteDataSource {
    override suspend fun login(username: String, password: String): Result<LoginResponse> {
        return client.runReader(endpoints) {
            it.login(ReaderLoginRequest(username = username, password = password, isLogin = true))
        }
    }

    override suspend fun getUserInfo(accessToken: String): Result<UserInfo> =
        client.runReader(endpoints) { it.getUserInfo(accessToken) }

    override suspend fun changePassword(accessToken: String, oldPass: String, newPass: String): Result<String> {
        return Result.failure(UnsupportedOperationException("当前服务端不支持修改密码"))
    }
}

private class ReadBookRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : BookRemoteDataSource {
    override suspend fun fetchBooks(accessToken: String): Result<List<Book>> =
        client.runRead(endpoints) { it.getBookshelf(accessToken) }

    override suspend fun fetchChapterList(accessToken: String, bookUrl: String, bookSourceUrl: String?): Result<List<Chapter>> =
        client.runRead(endpoints) { it.getChapterList(accessToken, bookUrl, bookSourceUrl) }

    override suspend fun fetchChapterContent(accessToken: String, bookUrl: String, bookSourceUrl: String?, index: Int, contentType: Int): Result<String> =
        client.runRead(endpoints) { it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl) }

    override suspend fun saveBookProgress(accessToken: String, bookUrl: String, index: Int, pos: Double, title: String?): Result<String> =
        client.runRead(endpoints) { it.saveBookProgress(accessToken, bookUrl, index, pos, title) }

    override suspend fun setBookSource(accessToken: String, bookUrl: String, newUrl: String, bookSourceUrl: String): Result<Book> =
        client.runRead(endpoints) { it.setBookSource(accessToken, bookUrl, newUrl, bookSourceUrl) }

    override suspend fun searchBook(accessToken: String, keyword: String, bookSourceUrl: String, page: Int): Result<List<Book>> =
        client.runRead(endpoints) { it.searchBook(accessToken, keyword, bookSourceUrl, page) }
}

private class ReaderBookRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : BookRemoteDataSource {
    override suspend fun fetchBooks(accessToken: String): Result<List<Book>> =
        client.runReader(endpoints) { it.getBookshelf(accessToken) }

    override suspend fun fetchChapterList(accessToken: String, bookUrl: String, bookSourceUrl: String?): Result<List<Chapter>> =
        client.runReader(endpoints) { it.getChapterList(accessToken, bookUrl, bookSourceUrl) }

    override suspend fun fetchChapterContent(accessToken: String, bookUrl: String, bookSourceUrl: String?, index: Int, contentType: Int): Result<String> =
        client.runReader(endpoints) { it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl) }

    override suspend fun saveBookProgress(accessToken: String, bookUrl: String, index: Int, pos: Double, title: String?): Result<String> =
        client.runReader(endpoints) {
            it.saveBookProgress(accessToken, ReaderSaveBookProgressRequest(url = bookUrl, index = index, pos = pos, title = title))
        }

    override suspend fun setBookSource(accessToken: String, bookUrl: String, newUrl: String, bookSourceUrl: String): Result<Book> =
        client.runReader(endpoints) {
            it.setBookSource(
                accessToken,
                ReaderSetBookSourceRequest(bookUrl = bookUrl, newUrl = newUrl, bookSourceUrl = bookSourceUrl)
            )
        }

    override suspend fun searchBook(accessToken: String, keyword: String, bookSourceUrl: String, page: Int): Result<List<Book>> =
        client.runReader(endpoints) { it.searchBook(accessToken, keyword, bookSourceUrl, page) }
}


private class ReadRssRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>,
    private val gson: Gson
) : RssRemoteDataSource {
    override suspend fun fetchSources(accessToken: String): Result<RssSourcesResponse> =
        client.runRead(endpoints) { it.getRssSources(accessToken) }

    override suspend fun toggleSource(accessToken: String, sourceUrl: String, isEnabled: Boolean): Result<Any> {
        val status = if (isEnabled) 1 else 0
        return client.runRead(endpoints) { it.stopRssSource(accessToken, sourceUrl, status) }
    }

    override suspend fun saveSource(accessToken: String, remoteId: String?, source: RssSourceItem): Result<Any> {
        val payload = RssEditPayload(
            json = gson.toJson(source.toPayload()),
            id = remoteId
        )
        return client.runRead(endpoints) { it.editRssSources(accessToken, payload) }
    }

    override suspend fun deleteSource(accessToken: String, sourceUrl: String): Result<Any> =
        client.runRead(endpoints) { it.deleteRssSource(accessToken, sourceUrl) }
}

private class ReaderRssRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : RssRemoteDataSource {
    override suspend fun fetchSources(accessToken: String): Result<RssSourcesResponse> =
        client.runReader(endpoints) { it.getRssSources(accessToken) }

    override suspend fun toggleSource(accessToken: String, sourceUrl: String, isEnabled: Boolean): Result<Any> {
        val status = if (isEnabled) 1 else 0
        return client.runReader(endpoints) { it.stopRssSource(accessToken, sourceUrl, status) }
    }

    override suspend fun saveSource(accessToken: String, remoteId: String?, source: RssSourceItem): Result<Any> =
        Result.failure(UnsupportedOperationException("当前服务端不支持远程编辑"))

    override suspend fun deleteSource(accessToken: String, sourceUrl: String): Result<Any> =
        Result.failure(UnsupportedOperationException("当前服务端不支持远程编辑"))
}

private class ReadReplaceRuleRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : ReplaceRuleRemoteDataSource {
    override suspend fun fetchReplaceRules(accessToken: String): Result<List<ReplaceRule>> {
        val pageInfoResult = client.runRead(endpoints) { it.getReplaceRulesPage(accessToken) }
        if (pageInfoResult.isFailure) return Result.failure(pageInfoResult.exceptionOrNull() ?: IllegalStateException("Failed to fetch page info"))
        val pageInfo = pageInfoResult.getOrThrow()
        val totalPages = pageInfo.page
        if (totalPages <= 0 || pageInfo.md5.isBlank()) return Result.success(emptyList())

        val rules = mutableListOf<ReplaceRule>()
        for (page in 1..totalPages) {
            val result = client.runRead(endpoints) { it.getReplaceRules(accessToken, pageInfo.md5, page) }
            if (result.isFailure) return Result.failure(result.exceptionOrNull() ?: IllegalStateException("Failed to fetch page $page"))
            rules.addAll(result.getOrThrow())
        }
        return Result.success(rules)
    }

    override suspend fun addReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any> =
        client.runRead(endpoints) { it.addReplaceRule(accessToken, rule) }

    override suspend fun deleteReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any> =
        client.runRead(endpoints) { it.deleteReplaceRule(accessToken, rule.id) }

    override suspend fun toggleReplaceRule(accessToken: String, rule: ReplaceRule, isEnabled: Boolean): Result<Any> =
        client.runRead(endpoints) {
            it.toggleReplaceRule(accessToken, rule.id, if (isEnabled) 1 else 0)
        }

    override suspend fun saveReplaceRules(accessToken: String, jsonContent: String): Result<Any> {
        val requestBody = jsonContent.toRequestBody("text/plain".toMediaTypeOrNull())
        return client.runRead(endpoints) { it.saveReplaceRules(accessToken, requestBody) }
    }
}

private class ReaderReplaceRuleRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : ReplaceRuleRemoteDataSource {
    override suspend fun fetchReplaceRules(accessToken: String): Result<List<ReplaceRule>> =
        client.runReader(endpoints) { it.getReplaceRules(accessToken) }

    override suspend fun addReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any> =
        client.runReader(endpoints) { it.saveReplaceRule(accessToken, rule) }

    override suspend fun deleteReplaceRule(accessToken: String, rule: ReplaceRule): Result<Any> =
        client.runReader(endpoints) { it.deleteReplaceRule(accessToken, rule) }

    override suspend fun toggleReplaceRule(accessToken: String, rule: ReplaceRule, isEnabled: Boolean): Result<Any> =
        client.runReader(endpoints) {
            it.saveReplaceRule(accessToken, rule.copy(isEnabled = isEnabled))
        }

    override suspend fun saveReplaceRules(accessToken: String, jsonContent: String): Result<Any> {
        val requestBody = jsonContent.toRequestBody("text/plain".toMediaTypeOrNull())
        return client.runReader(endpoints) { it.saveReplaceRules(accessToken, requestBody) }
    }
}

private class ReadTtsRemoteDataSource(
    private val client: FailoverClient,
    private val endpoints: List<String>
) : TtsRemoteDataSource {
    override suspend fun fetchTtsEngines(accessToken: String): Result<List<HttpTTS>> =
        client.runRead(endpoints) { it.getAllTts(accessToken) }

    override suspend fun fetchDefaultTts(accessToken: String): Result<String> =
        client.runRead(endpoints) { it.getDefaultTts(accessToken) }

    override suspend fun addTts(accessToken: String, tts: HttpTTS): Result<String> =
        client.runRead(endpoints) { it.addTts(accessToken, tts) }

    override suspend fun deleteTts(accessToken: String, id: String): Result<String> =
        client.runRead(endpoints) { it.delTts(accessToken, id) }

    override suspend fun saveTtsBatch(accessToken: String, json: String): Result<Any> {
        val requestBody = json.toRequestBody("text/plain".toMediaTypeOrNull())
        return client.runRead(endpoints) { it.saveTtsBatch(accessToken, requestBody) }
    }
}

private class ReaderTtsRemoteDataSource : TtsRemoteDataSource {
    override suspend fun fetchTtsEngines(accessToken: String): Result<List<HttpTTS>> =
        Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))

    override suspend fun fetchDefaultTts(accessToken: String): Result<String> =
        Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))

    override suspend fun addTts(accessToken: String, tts: HttpTTS): Result<String> =
        Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))

    override suspend fun deleteTts(accessToken: String, id: String): Result<String> =
        Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))

    override suspend fun saveTtsBatch(accessToken: String, json: String): Result<Any> =
        Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
}
