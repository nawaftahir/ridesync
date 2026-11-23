import java.net.URI
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Extracts the hostname from API_BASE_URL (dart-defines, local .env, or env var)
// so Android App Links work without hardcoding any domain in Git.
fun resolveAppLinkHost(): String {
    var apiBaseUrl: String? = null
    val dartDefines = project.findProperty("dart-defines") as? String
    if (!dartDefines.isNullOrBlank()) {
        for (encoded in dartDefines.split(",")) {
            val decoded = try {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            } catch (_: Exception) {
                ""
            }
            if (decoded.startsWith("API_BASE_URL=")) {
                apiBaseUrl = decoded.removePrefix("API_BASE_URL=").trim()
            }
        }
    }
    if (apiBaseUrl.isNullOrBlank()) {
        val envFile = rootProject.file("../.env")
        if (envFile.exists()) {
            envFile.readLines().forEach { line ->
                val trimmed = line.trim()
                if (trimmed.startsWith("API_BASE_URL=")) {
                    apiBaseUrl = trimmed.removePrefix("API_BASE_URL=").trim().trim('"', '\'')
                }
            }
        }
    }
    if (apiBaseUrl.isNullOrBlank()) {
        apiBaseUrl = System.getenv("API_BASE_URL")?.trim()
    }
    val raw = apiBaseUrl?.takeIf { it.isNotBlank() } ?: return "ridesync.invalid"
    return try {
        val normalized = if (raw.contains("://")) raw else "https://$raw"
        URI(normalized).host?.lowercase()?.takeIf { it.isNotBlank() } ?: "ridesync.invalid"
    } catch (_: Exception) {
        "ridesync.invalid"
    }
}

android {
    namespace = "com.example.ridesync"
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ridesync"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // MapLibre Native requires Android API 24+ (Android 7.0+).
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLinkHost"] = resolveAppLinkHost()
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
