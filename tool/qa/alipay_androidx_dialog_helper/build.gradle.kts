plugins {
    id("com.android.application") version "9.0.1" apply false
}

val isolatedBuildRoot = providers.gradleProperty("helperBuildRoot").orNull

allprojects {
    if (!isolatedBuildRoot.isNullOrBlank()) {
        layout.buildDirectory.set(file(isolatedBuildRoot).resolve(project.name))
    }
}
