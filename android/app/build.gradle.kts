import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Present only in CI (release.yml decodes the keystore to $RUNNER_TEMP). A local build without it
// still works and signs with the debug key.
val ksFile: String? = System.getenv("ANDROID_KEYSTORE_FILE")?.takeIf { it.isNotBlank() }

android {
    namespace = "com.rahul.marquee"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17     // R1: Temurin 17 everywhere
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // NEVER changes after the first install — it is the identity of every future update.
        applicationId = "com.rahul.marquee"
        minSdk = 26                          // R2: Android 8.0+
        targetSdk = 36
        versionCode = flutter.versionCode    // from --build-number
        versionName = flutter.versionName    // from --build-name
    }

    signingConfigs {
        create("release") {
            val path = ksFile
            if (path != null) {
                storeFile = File(path)
                storeType = "PKCS12"
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Keep R8 OFF: media_kit reaches libmpv through JNI and reflection, and a stripped
            // build fails at RUNTIME rather than at build time. Size is controlled by ABI splits
            // (`flutter build apk --split-per-abi`; never add a `splits { abi { … } }` block too).
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig =
                if (ksFile != null) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }

    packaging {
        // libmpv/ffmpeg .so files must stay page-aligned and uncompressed.
        jniLibs { useLegacyPackaging = false }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
