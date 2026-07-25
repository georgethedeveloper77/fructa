# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# OneSignal
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# local_auth (biometric)
-keep class androidx.biometric.** { *; }

# in_app_update
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep annotations and generic signatures (Riverpod / json models via reflection safety)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Suppress Play Core warnings from Flutter deferred components
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# WorkManager + Room (WorkManager is pulled in transitively by OneSignal).
# WorkManager stores its job queue in a Room database, WorkDatabase. Room builds
# its generated implementation by reflection as "<canonicalName>_Impl". R8 renames
# WorkDatabase and WorkDatabase_Impl, the reflective lookup misses, and the app
# crashes at process start via androidx.startup.InitializationProvider, before
# Flutter boots. Keep the original names so the lookup resolves.
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.RoomDatabase { *; }
-dontwarn androidx.room.**
-keep class androidx.startup.** { *; }

# flutter_local_notifications: the plugin serializes scheduled-notification
# details via GSON. R8 stripping its model classes (or generic signatures) makes
# a reboot-rescheduled reminder fail to deserialize. Signature is already kept
# above; keep the plugin's classes and GSON too.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
