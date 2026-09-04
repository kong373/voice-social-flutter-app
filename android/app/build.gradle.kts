import java.io.File
import java.io.FileInputStream
import java.security.KeyStore
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

private data class ReleaseSigningMaterial(
    val storeFile: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

private fun environmentValue(name: String): String? =
    System.getenv(name)?.takeUnless { it.isBlank() }

private fun requiredValue(values: Map<String, String?>, name: String): String =
    values[name]?.takeUnless { it.isBlank() }
        ?: error("required release signing material is missing: $name")

private fun readSigningProperties(file: File): Map<String, String?> {
    val properties = Properties()
    try {
        FileInputStream(file).use { properties.load(it) }
    } catch (_: Exception) {
        error("required release signing material is unreadable")
    }
    return mapOf(
        "storeFile" to properties.getProperty("storeFile"),
        "storePassword" to properties.getProperty("storePassword"),
        "keyAlias" to properties.getProperty("keyAlias"),
        "keyPassword" to properties.getProperty("keyPassword"),
    )
}

private fun loadReleaseSigningMaterial(): ReleaseSigningMaterial {
    val directEnvironment = mapOf(
        "storeFile" to environmentValue("ANDROID_RELEASE_STORE_FILE"),
        "storePassword" to environmentValue("ANDROID_RELEASE_STORE_PASSWORD"),
        "keyAlias" to environmentValue("ANDROID_RELEASE_KEY_ALIAS"),
        "keyPassword" to environmentValue("ANDROID_RELEASE_KEY_PASSWORD"),
    )
    val directEnvironmentConfigured = directEnvironment.values.any { it != null }
    val explicitPropertiesPath = environmentValue("ANDROID_RELEASE_SIGNING_PROPERTIES_FILE")
    val defaultPropertiesFile = File(rootProject.projectDir, "key.properties")
    val defaultPropertiesConfigured = defaultPropertiesFile.isFile
    require(!(explicitPropertiesPath != null && directEnvironmentConfigured)) {
        "required release signing material has ambiguous sources"
    }
    require(!(explicitPropertiesPath != null && defaultPropertiesConfigured)) {
        "required release signing material has ambiguous sources"
    }
    require(!(directEnvironmentConfigured && defaultPropertiesConfigured)) {
        "required release signing material has ambiguous sources"
    }

    val values: Map<String, String?>
    val baseDirectory: File
    if (explicitPropertiesPath != null) {
        val propertiesFile = File(explicitPropertiesPath)
        require(propertiesFile.isFile && propertiesFile.canRead()) {
            "required release signing material is unavailable"
        }
        values = readSigningProperties(propertiesFile)
        baseDirectory = propertiesFile.parentFile ?: rootProject.projectDir
    } else if (directEnvironmentConfigured) {
        values = directEnvironment
        baseDirectory = rootProject.projectDir
    } else {
        require(defaultPropertiesFile.isFile && defaultPropertiesFile.canRead()) {
            "required release signing material is missing"
        }
        values = readSigningProperties(defaultPropertiesFile)
        baseDirectory = defaultPropertiesFile.parentFile ?: rootProject.projectDir
    }

    val storeFileCandidate = File(requiredValue(values, "storeFile"))
    val storeFile = (if (storeFileCandidate.isAbsolute) {
        storeFileCandidate
    } else {
        File(baseDirectory, storeFileCandidate.path)
    }).let { candidate ->
        runCatching { candidate.canonicalFile }.getOrNull()
    }
    require(storeFile != null && storeFile.isFile && storeFile.canRead()) {
        "required release signing material has an invalid keystore"
    }

    val material = ReleaseSigningMaterial(
        storeFile = storeFile,
        storePassword = requiredValue(values, "storePassword"),
        keyAlias = requiredValue(values, "keyAlias"),
        keyPassword = requiredValue(values, "keyPassword"),
    )

    val supportedTypes = listOf(KeyStore.getDefaultType(), "JKS", "PKCS12").distinct()
    val validKeystore = supportedTypes.any { type ->
        runCatching {
            val keyStore = KeyStore.getInstance(type)
            FileInputStream(material.storeFile).use { input ->
                keyStore.load(input, material.storePassword.toCharArray())
            }
            require(keyStore.containsAlias(material.keyAlias))
            require(keyStore.getKey(material.keyAlias, material.keyPassword.toCharArray()) != null)
        }.isSuccess
    }
    require(validKeystore) {
        "required release signing material has an invalid keystore"
    }

    return material
}

private fun releaseTaskRequested(): Boolean =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.substringAfterLast(':').contains("release", ignoreCase = true)
    }

private val releaseSigningMaterial: ReleaseSigningMaterial? =
    if (releaseTaskRequested()) loadReleaseSigningMaterial() else null

android {
    namespace = "com.kong373.voice_social_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kong373.voice_social_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningMaterial?.let { material ->
                storeFile = material.storeFile
                storePassword = material.storePassword
                keyAlias = material.keyAlias
                keyPassword = material.keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

tasks.register("validateReleaseSigning") {
    group = "verification"
    description = "Validate release signing material without building an artifact."
    doLast {
        require(releaseSigningMaterial != null) {
            "required release signing material is missing"
        }
        println("release-signing=PASS")
    }
}

tasks.configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            if (releaseSigningMaterial == null) {
                error("required release signing material is missing")
            }
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
