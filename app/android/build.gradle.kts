allprojects {
    repositories {
        google()
        mavenCentral()
        // flutter_esp_ble_prov pulls Espressif's Android provisioning SDK
        // (com.github.espressif:esp-idf-provisioning-android) from JitPack.
        // The plugin declares this in its own build file, but that does not
        // affect how the *app* resolves its transitive dependencies.
        maven { url = uri("https://jitpack.io") }
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

/*
 * Backfill `namespace` for plugins written before AGP 8.
 *
 * flutter_esp_ble_prov 0.1.7 declares its package only in AndroidManifest.xml.
 * AGP 7 accepted that; AGP 8+ fails with "Namespace not specified". The plugin
 * is unmaintained, so rather than pin the whole project to an old AGP — which
 * would hold back every other dependency — read the package out of the
 * manifest and set it ourselves.
 *
 * This must be registered BEFORE the evaluationDependsOn(":app") block below.
 * That call forces evaluation, and anything hooked afterwards fails with
 * "Cannot run Project.afterEvaluate when the project is already evaluated".
 * plugins.withId fires as the Android plugin is applied, which is early enough.
 *
 * Scoped to subprojects actually missing a namespace, so it is a no-op for
 * correctly configured plugins and removes itself if the package is updated.
 */
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = project.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension &&
            androidExt.namespace == null
        ) {
            val manifest = project.file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val pkg = Regex("package\\s*=\\s*\"([^\"]+)\"")
                    .find(manifest.readText())
                    ?.groupValues?.get(1)
                if (pkg != null) {
                    logger.lifecycle(
                        "Backfilling namespace '" + pkg + "' for " + project.name
                    )
                    androidExt.namespace = pkg
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
