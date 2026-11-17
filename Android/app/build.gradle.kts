plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    testOptions {
        // Birim testlerinde android.util.Log gibi cagrilar varsayilan degerle donsun.
        unitTests.isReturnDefaultValues = true
    }
    namespace = "com.btekosistem.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.btekosistem.android"
        minSdk = 26
        targetSdk = 35
        // Surum: ./gradlew assembleRelease -PappVersion=1.2.3 [-PappVersionCode=10203]
        val appVersion = (project.findProperty("appVersion") as String?)?.removePrefix("v") ?: "0.1.0"
        val parts = appVersion.split("-")[0].split(".").map { it.toIntOrNull() ?: 0 }
        versionName = appVersion
        versionCode = (project.findProperty("appVersionCode") as String?)?.toIntOrNull()
            ?: (parts.getOrElse(0) { 0 } * 10000 + parts.getOrElse(1) { 0 } * 100 + parts.getOrElse(2) { 0 }).coerceAtLeast(1)
    }

    // Imza: ORBIO_KEYSTORE (dosya yolu), ORBIO_KEYSTORE_PASSWORD, ORBIO_KEY_ALIAS, ORBIO_KEY_PASSWORD
    // ortam degiskeni ya da gradle property olarak verilirse release o anahtarla imzalanir; yoksa debug imzasi.
    fun cfg(name: String): String? = (project.findProperty(name) as String?) ?: System.getenv(name)
    val releaseKeystore = cfg("ORBIO_KEYSTORE")?.takeIf { it.isNotBlank() && file(it).exists() }
    signingConfigs {
        if (releaseKeystore != null) {
            create("orbioRelease") {
                storeFile = file(releaseKeystore)
                storePassword = cfg("ORBIO_KEYSTORE_PASSWORD")
                keyAlias = cfg("ORBIO_KEY_ALIAS")
                keyPassword = cfg("ORBIO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystore != null) signingConfigs.getByName("orbioRelease")
                            else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    sourceSets {
        getByName("main").java.srcDir("src/main/kotlin")
        getByName("test").java.srcDir("src/test/kotlin")
    }
}

dependencies {
    val bom = platform(libs.androidx.compose.bom)
    implementation(bom)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.kotlinx.coroutines.android)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
}
