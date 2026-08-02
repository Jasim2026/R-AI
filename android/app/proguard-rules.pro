# Keep LiteRT-LM classes
-keep class com.google.ai.edge.litertlm.** { *; }

# Keep Kotlin coroutines (targeted)
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
# Keep SendChannel interface methods (litertlm-android calls SendChannel.close$default)
-keep class kotlinx.coroutines.channels.SendChannel { *; }
-keep class kotlinx.coroutines.channels.SendChannel$DefaultImpls { *; }

# Keep MediaPipe Text Embedding classes
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep Protobuf classes (required by MediaPipe)
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Ignore missing Play Core classes
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Ignore javax.annotation.processing (compile-time only, from auto-value)
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.com.squareup.javapoet$.**
