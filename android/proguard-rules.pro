# ReadApp ProGuard Rules
# 修复 java.lang.Class cannot be cast to java.lang.reflect.ParameterizedType 错误

# ==================== Retrofit ====================
# 保持 Retrofit 的泛型签名（R8 full mode 会删除泛型签名）
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response

# 保持 Retrofit 接口方法的泛型信息
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*

# 保持 Retrofit 服务接口
-keep interface * {
    @retrofit2.http.* <methods>;
}

# ==================== Kotlin Coroutines ====================
# 保持 Kotlin Coroutines 的 Continuation 泛型
# suspend 函数会被包装在 Continuation 中，需要保留类型参数
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

# ==================== Gson ====================
# Gson 使用反射，需要保持数据类的字段
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# 保持数据模型类（根据你的包名调整）
# 假设你的数据模型在 com.readapp.data.model 包下
-keep class com.readapp.data.model.** { *; }
-keep class com.readapp.data.** { *; }

# 防止 Gson 序列化时字段被混淆
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ==================== OkHttp ====================
# OkHttp 平台相关代码
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# OkHttp 使用的 Okio
-keep class okio.** { *; }
-dontwarn okio.**

# ==================== Jetpack Compose ====================
# 保持 Compose 相关的类
-keep class androidx.compose.** { *; }
-keep class androidx.lifecycle.** { *; }

# ==================== 数据类 ====================
# 保持所有 data class 的字段和构造函数
-keepclassmembers class * {
    public <init>(...);
}

-keep @kotlin.Metadata class *
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# ==================== 反射 ====================
# 保持使用反射的类不被混淆
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ==================== 序列化 ====================
# 如果使用了 Kotlin Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ==================== 保持 API 接口 ====================
# 保持你的 API Service 接口不被混淆
# 根据实际包名调整
-keep interface com.readapp.data.api.** { *; }
-keep class com.readapp.data.api.ApiService { *; }

# ==================== 保持枚举 ====================
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ==================== 移除日志 ====================
# Release 版本移除 Log 调用（可选）
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# ==================== 其他通用规则 ====================
# 保持 native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保持自定义 View
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
    public void set*(...);
}

# 保持 Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# 保持 Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ==================== 调试信息 ====================
# 保持行号信息，方便调试崩溃日志
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
