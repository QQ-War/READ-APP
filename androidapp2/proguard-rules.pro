# Keep generic type and annotation metadata for Retrofit + Gson to reflect response types
-keepattributes Signature,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations

# Keep Retrofit interfaces and their HTTP annotations
-keepclassmembers interface * {
    @retrofit2.http.* <methods>;
}
-keep class com.readapp.data.ReadApiService { *; }
-dontwarn retrofit2.**

# Keep model classes used with Gson/Retrofit
-keep class com.readapp.data.model.** { *; }

# Keep Gson reflection helpers to avoid type casting issues
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
