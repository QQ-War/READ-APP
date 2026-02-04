package com.readapp.data

import com.google.gson.GsonBuilder
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.data.model.BookSourcePageInfo
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.RssEditPayload
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.ReplaceRulePageInfo
import com.readapp.data.model.RssSourcesResponse
import com.readapp.data.model.UserInfo
import okhttp3.Interceptor
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import com.readapp.data.model.HttpTtsAdapter
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Query

interface ReadApiService {
    @POST(ApiEndpoints.Login)
    suspend fun login(
        @Query("username") username: String,
        @Query("password") password: String,
        @Query("model") model: String = "android",
        @Query("v") version: Int = 5
    ): Response<ApiResponse<LoginResponse>>

    @GET(ApiEndpoints.GetUserInfo)
    suspend fun getUserInfo(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<UserInfo>>

    @GET(ApiEndpoints.ChangePassword)
    suspend fun changePassword(
        @Query("accessToken") accessToken: String,
        @Query("oldpassword") oldPass: String,
        @Query("password") newPass: String
    ): Response<ApiResponse<String>>

    @GET(ApiEndpoints.GetAllTokens)
    suspend fun getAllTokens(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<String>>>

    @GET(ApiEndpoints.GetBookshelf)
    suspend fun getBookshelf(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<Book>>>

    @GET(ApiEndpoints.GetChapterList)
    suspend fun getChapterList(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<List<Chapter>>>

    @GET(ApiEndpoints.GetBookContent)
    suspend fun getBookContent(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("type") type: Int = 0,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<String>>

    @retrofit2.http.Streaming
    @GET(ApiEndpoints.GetChapterPackage)
    suspend fun getChapterPackage(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("type") type: Int = 2,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<okhttp3.ResponseBody>

    @GET(ApiEndpoints.SaveBookProgress)
    suspend fun saveBookProgress(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("pos") pos: Double,
        @Query("title") title: String?,
    ): Response<ApiResponse<String>>

    @GET(ApiEndpoints.SetBookSource)
    suspend fun setBookSource(
        @Query("accessToken") accessToken: String,
        @Query("bookUrl") bookUrl: String,
        @Query("newUrl") newUrl: String,
        @Query("bookSourceUrl") bookSourceUrl: String
    ): Response<ApiResponse<Book>>

    @GET(ApiEndpoints.GetAllTts)
    suspend fun getAllTts(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<HttpTTS>>>

    @GET(ApiEndpoints.GetDefaultTts)
    suspend fun getDefaultTts(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<String>>

    @POST(ApiEndpoints.AddTts)
    suspend fun addTts(
        @Query("accessToken") accessToken: String,
        @Body tts: HttpTTS
    ): Response<ApiResponse<String>>

    @POST(ApiEndpoints.DeleteTts)
    suspend fun delTts(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<String>>

    @POST(ApiEndpoints.SaveTtsBatch)
    suspend fun saveTtsBatch(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody
    ): Response<ApiResponse<Any>>

    @Multipart
    @POST(ApiEndpoints.ImportBookPreview)
    suspend fun importBook(
        @Query("accessToken") accessToken: String,
        @Part file: MultipartBody.Part
    ): Response<ApiResponse<Any>>

    // region Replace Rules
    @GET(ApiEndpoints.GetReplaceRulesPage)
    suspend fun getReplaceRulesPage(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<ReplaceRulePageInfo>>

    @GET(ApiEndpoints.GetReplaceRules)
    suspend fun getReplaceRules(
        @Query("accessToken") accessToken: String,
        @Query("md5") md5: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<ReplaceRule>>>

    @POST(ApiEndpoints.AddReplaceRule)
    suspend fun addReplaceRule(
        @Query("accessToken") accessToken: String,
        @Body rule: ReplaceRule
    ): Response<ApiResponse<Any>>
    
    @POST(ApiEndpoints.DeleteReplaceRule)
    suspend fun deleteReplaceRule(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Any>>

    @POST(ApiEndpoints.ToggleReplaceRule)
    suspend fun toggleReplaceRule(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: Int
    ): Response<ApiResponse<Any>>

    @POST(ApiEndpoints.SaveReplaceRules)
    suspend fun saveReplaceRules(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody
    ): Response<ApiResponse<Any>>
    // endregion

    // region Book Sources
    @GET(ApiEndpoints.GetBookSourcesPage)
    suspend fun getBookSourcesPage(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<BookSourcePageInfo>>

    @GET(ApiEndpoints.GetBookSources)
    suspend fun getBookSourcesNew(
        @Query("accessToken") accessToken: String,
        @Query("md5") md5: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<BookSource>>>

    @POST(ApiEndpoints.SaveBookSource)
    suspend fun saveBookSource(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody
    ): Response<ApiResponse<Any>>

    @GET(ApiEndpoints.DeleteBookSource)
    suspend fun deleteBookSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Any>>

    @GET(ApiEndpoints.ToggleBookSource)
    suspend fun toggleBookSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: String
    ): Response<ApiResponse<Any>>

    @GET(ApiEndpoints.GetBookSourceDetail)
    suspend fun getBookSourceDetail(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Map<String, Any>>>

    @GET(ApiEndpoints.GetExploreUrl)
    suspend fun getExploreUrl(
        @Query("accessToken") accessToken: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("need") need: String = "true"
    ): Response<ApiResponse<Map<String, String>>>

    @GET(ApiEndpoints.ExploreBook)
    suspend fun exploreBook(
        @Query("accessToken") accessToken: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("ruleFindUrl") ruleFindUrl: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<Book>>>
    
    @GET(ApiEndpoints.GetRssSources)
    suspend fun getRssSources(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<RssSourcesResponse>>

    @GET(ApiEndpoints.StopRssSource)
    suspend fun stopRssSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: Int
    ): Response<ApiResponse<Any>>

    @POST(ApiEndpoints.EditRssSources)
    suspend fun editRssSources(
        @Query("accessToken") accessToken: String,
        @Body payload: RssEditPayload,
    ): Response<ApiResponse<Any>>

    @GET(ApiEndpoints.DeleteRssSource)
    suspend fun deleteRssSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
    ): Response<ApiResponse<Any>>
    // endregion

    // region Book Search
    @GET(ApiEndpoints.SearchBook)
    suspend fun searchBook(
        @Query("accessToken") accessToken: String,
        @Query("key") keyword: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<Book>>>

    @POST(ApiEndpoints.SaveBook)
    suspend fun saveBook(
        @Query("accessToken") accessToken: String,
        @Query("useReplaceRule") useReplaceRule: Int = 0,
        @Body book: Book
    ): Response<ApiResponse<Any>>

    @POST(ApiEndpoints.DeleteBook)
    suspend fun deleteBook(
        @Query("accessToken") accessToken: String,
        @Body book: Book
    ): Response<ApiResponse<Any>>
    // endregion

    companion object {
        fun create(baseUrl: String, tokenProvider: () -> String): ReadApiService {
            val authInterceptor = Interceptor { chain ->
                val original = chain.request()
                val token = tokenProvider()
                val builder = original.newBuilder()
                if (token.isNotBlank()) {
                    builder.header("Authorization", "Bearer $token")
                }
                val newRequest = builder.build()
                chain.proceed(newRequest)
            }

            val logging = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            }

            val client = OkHttpClient.Builder()
                .addInterceptor(authInterceptor)
                .addInterceptor(logging)
                .build()

            return Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(client)
                .addConverterFactory(
                    GsonConverterFactory.create(
                        GsonBuilder()
                            .registerTypeAdapter(HttpTTS::class.java, HttpTtsAdapter())
                            .serializeNulls()
                            .create()
                    )
                )
                .build()
                .create(ReadApiService::class.java)
        }
    }
}
