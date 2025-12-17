package com.readapp.data

import com.google.gson.GsonBuilder
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.UserInfo
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.GET
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
