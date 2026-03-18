plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    // alias(libs.plugins.google.services)  // re-enable after adding google-services.json
}

android {
    namespace = "com.theholylabs.creator"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.theholylabs.creator"
        minSdk = 26
        targetSdk = 35
        versionCode = 2
        versionName = "2.0"

        // API base URL — override in local.properties or CI env
        buildConfigField("String", "API_BASE_URL", "\"https://api.holylabs.net\"")
    }

    signingConfigs {
        create("release") {
            storeFile = file("/Users/admin/Documents/creatorai-release.jks")
            storePassword = "creatorai2024"
            keyAlias = "creatorai"
            keyPassword = "creatorai2024"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            isDebuggable = true
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.lifecycle.viewmodel)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.security.crypto)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons.extended)
    debugImplementation(libs.compose.ui.tooling)

    implementation(libs.revenuecat)
    implementation(libs.revenuecat.ui)

    implementation(libs.appsflyer)
    implementation(libs.install.referrer)
    implementation("io.coil-kt:coil-compose:2.5.0")
    implementation("io.coil-kt:coil-video:2.5.0")

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.gotrue)
    implementation(libs.supabase.postgrest)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.play.services.auth)
    implementation(libs.coroutines.android)
    implementation(libs.appcompat)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
}
