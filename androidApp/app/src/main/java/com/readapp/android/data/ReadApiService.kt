package com.readapp.android.data

import com.readapp.android.model.ApiResponse
import com.readapp.android.model.Book
import com.readapp.android.model.BookChapter
import com.readapp.android.model.HttpTTS
import com.readapp.android.model.LoginResponse
import com.readapp.android.model.UserInfo
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.GET
import retrofit2.http.Query

interface ReadApiService {
    @GET("login")
    suspend fun login(
        @Query("username") username: String,
        @Query("password") password: String,
        @Query("model") model: String = "android"
    ): Response<ApiResponse<LoginResponse>>

    @GET("getUserInfo")
    suspend fun getUserInfo(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<UserInfo>>

    @GET("getBookshelf")
    suspend fun getBookshelf(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<List<Book>>>

    @GET("getChapterList")
    suspend fun getChapterList(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("bookSourceUrl") bookSourceUrl: String? = null
    ): Response<ApiResponse<List<BookChapter>>>

    @GET("getBookContent")
    suspend fun getBookContent(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("type") type: Int = 0,
        @Query("bookSourceUrl") bookSourceUrl: String? = null
    ): Response<ApiResponse<String>>

    @GET("saveBookProgress")
    suspend fun saveBookProgress(
        @Query("accessToken") accessToken: String,
        @Query("url") url: String,
        @Query("index") index: Int,
        @Query("pos") pos: Double,
        @Query("title") title: String?
    ): Response<ApiResponse<String>>

    @GET("getalltts")
    suspend fun getAllTts(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<List<HttpTTS>>>

    @GET("getdefaulttts")
    suspend fun getDefaultTts(
        @Query("accessToken") accessToken: String
    ): Response<ApiResponse<String>>

    companion object {
        fun create(baseUrl: String, tokenProvider: () -> String): ReadApiService {
            val authInterceptor = Interceptor { chain ->
                val original = chain.request()
                val newRequest = original.newBuilder()
                    .header("Authorization", tokenProvider())
                    .build()
                chain.proceed(newRequest)
            }

            val logging = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            }

            val client = OkHttpClient.Builder()
                .addInterceptor(authInterceptor)
                .addInterceptor(logging)
                .build()

            val moshi = Moshi.Builder()
                .add(KotlinJsonAdapterFactory())
                .build()

            return Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(client)
                .addConverterFactory(MoshiConverterFactory.create(moshi))
                .build()
                .create(ReadApiService::class.java)
        }
    }
}
