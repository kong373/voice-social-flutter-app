group = "com.kong373.alipay_app_pay"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.kong373.alipay_app_pay"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

}

dependencies {
    // Pin the official Alipay Android SDK. The Flutter layer receives no app
    // private key, public key, certificate, or amount authority.
    implementation("com.alipay.sdk:alipaysdk-android:15.8.42")
    testImplementation("junit:junit:4.13.2")
    // Local JVM tests exercise the strict JSON contract with a real parser;
    // Android's mockable android.jar otherwise stubs org.json methods.
    testImplementation("org.json:json:20240303")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
