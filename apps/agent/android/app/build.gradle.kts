import java.util.Properties

// Clé de signature hors du dépôt : GUIS_SIGNING, sinon
// ~/.guis-keystore/signing.properties. Absente, la construction release échoue :
// une APK signée avec la clé de debug ne pourrait jamais être mise à jour par
// l'APK signée de production (il faudrait désinstaller, et perdre les saisies non
// envoyées). Pour un essai local ou une PR, GUIS_ALLOW_DEBUG_SIGNING=1 l'autorise.
val signingFile = file(System.getenv("GUIS_SIGNING")
    ?: "${System.getProperty("user.home")}/.guis-keystore/signing.properties")
val signing = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }
val allowDebugSigning = System.getenv("GUIS_ALLOW_DEBUG_SIGNING") == "1"

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.guis.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.guis.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Vérifié au début de la construction release seulement (debug et tests ne sont pas concernés).
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!signingFile.exists() && !allowDebugSigning) {
            throw GradleException(
                "Clé de signature release absente (${signingFile.path}). " +
                    "Voir apps/agent/README.md, ou GUIS_ALLOW_DEBUG_SIGNING=1 pour une APK d'essai non distribuable.",
            )
        }
    }
}
