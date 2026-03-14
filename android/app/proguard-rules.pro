# RevenueCat
-keep class com.revenuecat.purchases.** { *; }

# AppsFlyer
-keep class com.appsflyer.** { *; }
-keep class com.android.installreferrer.** { *; }

# Supabase / Ktor
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Kotlin serialization
-keepattributes *Annotation*
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class **$$serializer { *; }
