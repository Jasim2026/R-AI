# Keep LiteRT-LM classes
-keep class com.google.ai.edge.litertlm.** { *; }

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }

# Keep Flutter platform channel classes
-keep class io.flutter.** { *; }

# Keep model classes for serialization
-keep class com.example.r_ai.models.** { *; }

# Keep ObjectBox classes
-keep class io.objectbox.** { *; }
-keep class com.example.r_ai.entity.** { *; }
-dontwarn io.objectbox.**

# Keep MediaPipe Text Embedding classes
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Ignore missing Play Core classes (not needed for non-split APKs)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Ignore missing javax.annotation.processing classes (compile-time only, from auto-value)
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.com.squareup.javapoet$.**
