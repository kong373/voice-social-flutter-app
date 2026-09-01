plugins {
    id("com.android.application")
}

android {
    namespace = "com.kong373.voicesocial.qa.alipayhelper"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.kong373.voicesocial.qa.alipayhelper"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    testOptions {
        animationsDisabled = true
    }
}

dependencies {
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")
}
