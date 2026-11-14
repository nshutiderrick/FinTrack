import java.util.Properties

// The daily app's permanent signing key (android/key.properties, git-ignored).
// Updates only install over the app if they are signed with the same key.
val releaseKey = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.personal.expense_tracker"
    // flutter_local_notifications needs 37.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Scheduled reminders (flutter_local_notifications) need it.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.personal.expense_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two apps that can be installed side by side:
    //  capture: keeps the original package (and the alerts it already saved), capture on.
    //  daily:   the app for everyday use, capture off.
    // Needed for the per-flavor app_name and capture_default below.
    buildFeatures {
        resValues = true
    }

    signingConfigs {
        create("release") {
            if (releaseKey.isNotEmpty()) {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    flavorDimensions += "use"
    productFlavors {
        create("capture") {
            dimension = "use"
            // Stays on the debug key it was first installed with, so updates keep its saved alerts.
            signingConfig = signingConfigs.getByName("debug")
            resValue("string", "app_name", "FinTrack Capture")
            resValue("bool", "capture_default", "true")
            // Off, so ET Capture and Expense Tracker do not both pop up; switch on in Settings to test.
            resValue("bool", "popup_default", "false")
        }
        create("daily") {
            dimension = "use"
            applicationIdSuffix = ".daily"
            signingConfig = signingConfigs.getByName(if (releaseKey.isNotEmpty()) "release" else "debug")
            resValue("string", "app_name", "FinTrack")
            resValue("bool", "capture_default", "false")
            resValue("bool", "popup_default", "true")
        }
    }

    buildTypes {
        release {
            // Signing comes from the flavor (see productFlavors above).
        }
    }
}

dependencies {
    // Reads statement PDFs on the phone (Apache 2.0).
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
