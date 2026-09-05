allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

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

// Some plugins (e.g. flutter_secure_storage 11.x) hardcode compileSdk = 37,
// but the only API 37 platform packages available right now are fractional
// releases (android-37.0, android-37.1, ...) with no plain "android-37"
// target — current AGP can't resolve that hash. Force every plugin
// subproject onto the stable, already-installed API 36 instead.
subprojects {
    val forceCompileSdk36: () -> Unit = {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { android ->
            android.compileSdkVersion(36)
        }
    }
    // evaluationDependsOn(":app") above already forces some subprojects to
    // evaluate eagerly, so afterEvaluate{} on those throws "already
    // evaluated" — apply immediately in that case instead.
    if (state.executed) forceCompileSdk36() else afterEvaluate { forceCompileSdk36() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
