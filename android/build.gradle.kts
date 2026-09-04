allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter 3.44.7 uses compileSdk 36. Agora 6.6.3 reads this legacy root
// property during project evaluation and otherwise defaults its library to
// compileSdk 31, which is below its AndroidX metadata requirements.
extra["compileSdkVersion"] = 36

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
