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

# R8 missing class warnings
-dontwarn java.lang.management.ManagementFactory
-dontwarn java.lang.management.RuntimeMXBean
-dontwarn org.slf4j.impl.StaticLoggerBinder

# Kotlin serialization
-keepattributes *Annotation*
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class **$$serializer { *; }
