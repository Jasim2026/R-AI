# Keep LiteRT-LM classes
-keep class com.google.ai.edge.litertlm.** { *; }

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }

# Keep Flutter platform channel classes
-keep class io.flutter.** { *; }

# Keep model classes for serialization
-keep class com.example.r_ai.models.** { *; }

# Ignore missing Play Core classes (not needed for non-split APKs)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
