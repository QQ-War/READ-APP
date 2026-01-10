package com.readapp.data

import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.ReaderBookTtsRequest
import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.RssSourcesResponse
import com.readapp.data.model.UserInfo
import okhttp3.Interceptor
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Query

interface ReaderApiService {
    @POST(ReaderApiEndpoints.Login)
    suspend fun login(
        @Body request: ReaderLoginRequest,
    ): Response<ApiResponse<LoginResponse>>

    @GET(ReaderApiEndpoints.GetUserInfo)
    suspend fun getUserInfo(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<UserInfo>>

    @GET(ReaderApiEndpoints.GetBookshelf)
    suspend fun getBookshelf(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<Book>>>

    @GET(ReaderApiEndpoints.GetChapterList)
    suspend fun getChapterList(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<List<Chapter>>>

    @GET(ReaderApiEndpoints.GetBookContent)
    suspend fun getBookContent(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("type") type: Int = 0,
        @Query("bookSourceUrl") bookSourceUrl: String? = null,
    ): Response<ApiResponse<String>>

    @POST(ReaderApiEndpoints.SaveBookProgress)
    suspend fun saveBookProgress(
        @Query("accessToken") accessToken: String,
        @Body request: ReaderSaveBookProgressRequest,
    ): Response<ApiResponse<String>>

    @POST(ReaderApiEndpoints.SetBookSource)
    suspend fun setBookSource(
        @Query("accessToken") accessToken: String,
        @Body request: ReaderSetBookSourceRequest,
    ): Response<ApiResponse<Book>>

    @GET(ReaderApiEndpoints.SearchBook)
    suspend fun searchBook(
        @Query("accessToken") accessToken: String,
        @Query("key") keyword: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("page") page: Int,
    ): Response<ApiResponse<List<Book>>>

    @GET(ReaderApiEndpoints.ExploreBook)
    suspend fun exploreBook(
        @Query("accessToken") accessToken: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
        @Query("ruleFindUrl") ruleFindUrl: String,
        @Query("page") page: Int,
    ): Response<ApiResponse<List<Book>>>

    @POST(ReaderApiEndpoints.SaveBook)
    suspend fun saveBook(
        @Query("accessToken") accessToken: String,
        @Body book: Book,
    ): Response<ApiResponse<Any>>

    @POST(ReaderApiEndpoints.DeleteBook)
    suspend fun deleteBook(
        @Query("accessToken") accessToken: String,
        @Body book: Book,
    ): Response<ApiResponse<Any>>

    @GET(ReaderApiEndpoints.GetBookSources)
    suspend fun getBookSources(
        @Query("accessToken") accessToken: String,
        @Query("simple") simple: Int = 0,
    ): Response<ApiResponse<List<BookSource>>>

    @GET(ReaderApiEndpoints.GetBookSource)
    suspend fun getBookSource(
        @Query("accessToken") accessToken: String,
        @Query("bookSourceUrl") bookSourceUrl: String,
    ): Response<ApiResponse<JsonObject>>

    @POST(ReaderApiEndpoints.SaveBookSource)
    suspend fun saveBookSource(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody,
    ): Response<ApiResponse<Any>>

    @POST(ReaderApiEndpoints.SaveBookSources)
    suspend fun saveBookSources(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody,
    ): Response<ApiResponse<Any>>

    @POST(ReaderApiEndpoints.DeleteBookSource)
    suspend fun deleteBookSource(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody,
    ): Response<ApiResponse<Any>>

    @GET(ReaderApiEndpoints.GetReplaceRules)
    suspend fun getReplaceRules(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<List<ReplaceRule>>>

    @POST(ReaderApiEndpoints.SaveReplaceRule)
    suspend fun saveReplaceRule(
        @Query("accessToken") accessToken: String,
        @Body rule: ReplaceRule,
    ): Response<ApiResponse<Any>>

    @POST(ReaderApiEndpoints.SaveReplaceRules)
    suspend fun saveReplaceRules(
        @Query("accessToken") accessToken: String,
        @Body content: RequestBody,
    ): Response<ApiResponse<Any>>

    @POST(ReaderApiEndpoints.DeleteReplaceRule)
    suspend fun deleteReplaceRule(
        @Query("accessToken") accessToken: String,
        @Body rule: ReplaceRule,
    ): Response<ApiResponse<Any>>

    @GET(ReaderApiEndpoints.GetRssSources)
    suspend fun getRssSources(
        @Query("accessToken") accessToken: String,
    ): Response<ApiResponse<RssSourcesResponse>>

    @GET(ReaderApiEndpoints.HttpTtsList)
    suspend fun getHttpTtsList(
        @Query("accessToken") accessToken: String,
        @Query("v") version: Long,
    ): Response<ApiResponse<List<HttpTTS>>>

    @POST(ReaderApiEndpoints.BookTts)
    suspend fun requestBookTts(
        @Query("accessToken") accessToken: String,
        @Query("v") version: Long,
        @Body request: ReaderBookTtsRequest,
    ): Response<ApiResponse<String>>

    @GET(ReaderApiEndpoints.StopRssSource)
    suspend fun stopRssSource(
        @Query("accessToken") accessToken: String,
        @Query("id") id: String,
        @Query("st") status: Int
    ): Response<ApiResponse<Any>>

    @Multipart
    @POST(ReaderApiEndpoints.ImportBookPreview)
    suspend fun importBook(
        @Query("accessToken") accessToken: String,
        @Part file: MultipartBody.Part,
    ): Response<ApiResponse<Any>>

    companion object {
        fun create(baseUrl: String, tokenProvider: () -> String): ReaderApiService {
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
                .create(ReaderApiService::class.java)
        }
    }
}

data class ReaderLoginRequest(
    val username: String,
    val password: String,
    val isLogin: Boolean = true,
)

data class ReaderSaveBookProgressRequest(
    val url: String,
    val index: Int,
    val pos: Double? = null,
    val title: String? = null,
)

data class ReaderSetBookSourceRequest(
    val bookUrl: String,
    val newUrl: String,
    val bookSourceUrl: String,
)
