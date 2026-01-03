package com.readapp.data

import com.google.gson.GsonBuilder
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.data.model.BookSourcePageInfo
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.ReplaceRulePageInfo
import com.readapp.data.model.UserInfo
import okhttp3.Interceptor
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Query

interface ReadApiService {
    @GET("login")
    suspend fun login(
        @Query("username") username: String,
        @Query("password") password: String,
        @Query("model") model: String = "android",
    ): Response<ApiResponse<LoginResponse>>

    @GET("getUserInfo")
    suspend fun getUserInfo(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<UserInfo>>

    @GET("getBookshelf")
    suspend fun getBookshelf(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<Book>>>

    @GET("getChapterList")
    suspend fun getChapterList(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<List<Chapter>>>

    @GET("getBookContent")
    suspend fun getBookContent(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("type") type: Int = 0,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<String>>

    @GET("saveBookProgress")
    suspend fun saveBookProgress(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("pos") pos: Double,
        @Query("title") title: String?,
    ): Response<ApiResponse<String>>

    @GET("getalltts")
    suspend fun getAllTts(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<HttpTTS>>>

    @GET("getdefaulttts")
    suspend fun getDefaultTts(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<String>>

    @POST("addtts")
    suspend fun addTts(
        @Query("accessToken") accessToken: String,
        @Body tts: HttpTTS
    ): Response<ApiResponse<String>>

    @POST("deltts")
    suspend fun delTts(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<String>>

    @Multipart
    @POST("importBookPreview")
    suspend fun importBook(
        @Query("accessToken") accessToken: String,
        @Part file: MultipartBody.Part
    ): Response<ApiResponse<Any>>

    // region Replace Rules
    @GET("getReplaceRulesPage")
    suspend fun getReplaceRulesPage(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<ReplaceRulePageInfo>>

    @GET("getReplaceRulesNew")
    suspend fun getReplaceRules(
        @Query("accessToken") accessToken: String,
        @Query("md5") md5: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<ReplaceRule>>>

    @POST("addReplaceRule")
    suspend fun addReplaceRule(
        @Query("accessToken") accessToken: String,
        @Body rule: ReplaceRule
    ): Response<ApiResponse<Any>>
    
    @POST("delReplaceRule")
    suspend fun deleteReplaceRule(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Any>>

    @POST("stopReplaceRules")
    suspend fun toggleReplaceRule(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: Int
    ): Response<ApiResponse<Any>>
    // endregion

    // region Book Sources
    @GET("getBookSourcesPage")
    suspend fun getBookSourcesPage(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<BookSourcePageInfo>>

    @GET("getBookSourcesNew")
    suspend fun getBookSourcesNew(
        @Query("accessToken") accessToken: String,
        @Query("md5") md5: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<BookSource>>>

    @POST("saveBookSource")
    suspend fun saveBookSource(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody
    ): Response<ApiResponse<Any>>

    @GET("delbookSource")
    suspend fun deleteBookSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Any>>

    @GET("stopbookSource")
    suspend fun toggleBookSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: String
    ): Response<ApiResponse<Any>>

    @GET("getbookSources")
    suspend fun getBookSourceDetail(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String
    ): Response<ApiResponse<Map<String, Any>>>
    // endregion

    // region Book Search
    @GET("searchBook")
    suspend fun searchBook(
        @Query("accessToken") accessToken: String,
        @Query("key") keyword: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("page") page: Int
    ): Response<ApiResponse<List<Book>>>

    @POST("saveBook")
    suspend fun saveBook(
        @Query("accessToken") accessToken: String,
        @Query("useReplaceRule") useReplaceRule: Int = 0,
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
                    builder.header("Authorization", token)
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
                            .serializeNulls()
                            .create()
                    )
                )
                .build()
                .create(ReadApiService::class.java)
        }
    }
}
