# Keep generic type information so Gson can deserialize parameterized types
-keepattributes Signature
-keepattributes *Annotation*

# Keep model classes used in network responses
-keep class com.readapp.data.model.** { *; }

# Keep Gson library classes that rely on reflection
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
