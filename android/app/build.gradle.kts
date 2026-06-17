import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.costoda.dittoedgestudio"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.costoda.dittoedgestudio"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    packaging {
        resources {
            // mockk-android pulls in JUnit 5 (Jupiter) transitively, which includes multiple
            // copies of LICENSE.md / LICENSE-notice.md. Exclude them to avoid merge conflicts.
            excludes += setOf(
                "META-INF/LICENSE.md",
                "META-INF/LICENSE-notice.md",
            )
        }
    }
    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
    }

    // Expose the Room-exported schema JSONs to androidTest so MigrationTestHelper
    // can load them via assets. The schemas/ directory is checked into git
    // (see plans/android/config-loss-investigation.md item B1).
    sourceSets {
        named("androidTest") {
            assets.srcDirs("$projectDir/schemas")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

// Sync help docs from the central docs/help/ directory at the repo root.
val syncHelpDocs by tasks.registering(Copy::class) {
    description = "Copies help markdown files from docs/help/ into assets/help/"
    from(rootProject.file("../docs/help"))
    into(layout.projectDirectory.dir("src/main/assets/help"))
    include("*.md")
}

tasks.named("preBuild") {
    dependsOn(syncHelpDocs)
}

val forbidNonAdaptiveSizeApis by tasks.registering {
    group = "verification"
    description = "Fails if Configuration.screenWidthDp-style APIs are used outside ui/adaptive/"
    val srcDir = layout.projectDirectory.dir("src/main/java")
    inputs.dir(srcDir)
    doLast {
        val forbidden = Regex("""screenWidthDp|smallestScreenWidthDp""")
        val offenders = srcDir.asFileTree.matching {
            include("**/*.kt")
            exclude("**/ui/adaptive/**")
        }
            .filter { it.readText().contains(forbidden) }
            .map { it.relativeTo(srcDir.asFile) }
        if (offenders.isNotEmpty()) {
            throw GradleException(
                "Non-adaptive size APIs found (use ui/adaptive/WindowSize.kt instead):\n" +
                    offenders.joinToString("\n")
            )
        }
    }
}

tasks.named("check") { dependsOn(forbidNonAdaptiveSizeApis) }

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.core)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.window)
    implementation(libs.androidx.window.core)
    implementation(libs.material3.adaptive)
    implementation(libs.material3.adaptive.layout)
    implementation(libs.material3.adaptive.navigation3)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // SQLCipher + Room
    implementation(libs.sqlcipher)
    implementation(libs.androidx.sqlite)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Koin
    implementation(platform(libs.koin.bom))
    implementation(libs.koin.core)
    implementation(libs.koin.android)
    implementation(libs.koin.androidx.compose)

    // Navigation
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)

    // Coroutines
    implementation(libs.kotlinx.coroutines.android)

    // Ditto SDK
    implementation(libs.ditto.kotlin)

    // Markdown rendering (for Help inspector)
    implementation(libs.markwon.core)
    implementation(libs.markwon.html)
    implementation(libs.markwon.tables)
    implementation(libs.markwon.linkify)

    // Logging
    implementation(libs.timber)

    // QR Code — ML Kit barcode scanning + CameraX + ZXing + serialization
    implementation(libs.mlkit.barcode)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.zxing.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)

    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)

    // Unit tests
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.org.json)
    testImplementation(libs.okhttp.mockwebserver)

    // Instrumented tests
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.rules)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test)
    androidTestImplementation(libs.androidx.ui.test.junit4)
    androidTestImplementation(libs.room.testing)
    androidTestImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.mockk.android)
    androidTestImplementation(libs.okhttp.mockwebserver)
}
