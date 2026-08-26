plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningDirectory = providers
    .environmentVariable("TS_PHONE_SIGNING_DIR")
    .orNull
    ?.let { file(it) }
val releaseKeystore = releaseSigningDirectory?.resolve("ts-phone-release.p12")
val releasePasswordFile = releaseSigningDirectory?.resolve("keystore.pass")
val releasePassword = releasePasswordFile
    ?.takeIf { it.isFile }
    ?.readText()
    ?.trim()
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested &&
    (releaseKeystore?.isFile != true || releasePassword.isNullOrEmpty())
) {
    throw GradleException(
        "Release signing is unavailable. Set TS_PHONE_SIGNING_DIR to the " +
            "protected TS Phone signing directory.",
    )
}

android {
    namespace = "xyz.iawnix.ts_phone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "xyz.iawnix.ts_phone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseKeystore?.isFile == true && !releasePassword.isNullOrEmpty()) {
                storeFile = releaseKeystore
                storeType = "PKCS12"
                storePassword = releasePassword
                keyAlias = "ts-phone-release"
                keyPassword = releasePassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            ndk.debugSymbolLevel = "SYMBOL_TABLE"
        }
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
