package com.readapp.data

import com.readapp.data.model.ApiResponse
import retrofit2.Response as RetrofitResponse

class FailoverClient(
    private val apiFactory: (String) -> ReadApiService,
    private val readerApiFactory: (String) -> ReaderApiService
) {

    suspend fun <T> runRead(endpoints: List<String>, block: suspend (ReadApiService) -> RetrofitResponse<ApiResponse<T>>): Result<T> {
        return execute(endpoints, apiFactory, block)
    }

    suspend fun <T> runReader(endpoints: List<String>, block: suspend (ReaderApiService) -> RetrofitResponse<ApiResponse<T>>): Result<T> {
        return execute(endpoints, readerApiFactory, block)
    }

    private suspend fun <Service, T> execute(
        endpoints: List<String>,
        factory: (String) -> Service,
        block: suspend (Service) -> RetrofitResponse<ApiResponse<T>>
    ): Result<T> where Service : Any {
        var lastError: Throwable? = null
        for (endpoint in endpoints) {
            val service = factory(endpoint)
            try {
                val response = block(service)
                val result = handleResponse(response)
                if (result.isSuccess) {
                    return result
                }
                lastError = result.exceptionOrNull()
            } catch (e: Exception) {
                lastError = e
            }
        }
        return Result.failure(lastError ?: IllegalStateException("未知错误"))
    }

    private fun <T> handleResponse(response: RetrofitResponse<ApiResponse<T>>): Result<T> {
        if (response.isSuccessful) {
            val body = response.body()
            if (body != null) {
                if (body.isSuccess) {
                    @Suppress("UNCHECKED_CAST")
                    return Result.success(body.data ?: Unit as T)
                }
                return Result.failure(IllegalStateException(body.errorMsg ?: "未知错误"))
            }
            return Result.failure(IllegalStateException("响应体为空"))
        }
        return Result.failure(IllegalStateException("服务器返回状态码 ${response.code()}"))
    }
}
