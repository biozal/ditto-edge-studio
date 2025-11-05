import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.AbstractKotlinCompileTool
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.util.*

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    alias(libs.plugins.composeHotReload)
}

kotlin {
    androidTarget {
        @OptIn(ExperimentalKotlinGradlePluginApi::class)
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64()
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "ComposeApp"
            isStatic = true
        }
    }

    jvm()

    sourceSets {
        commonMain {
            // Add generated sources directory
            kotlin.srcDir(layout.buildDirectory.dir("generated-sources"))
        }
        androidMain.dependencies {
            implementation(compose.preview)
            implementation(libs.androidx.activity.compose)
        }
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation(compose.components.resources)
            implementation(compose.components.uiToolingPreview)
            implementation(libs.androidx.lifecycle.viewmodelCompose)
            implementation(libs.androidx.lifecycle.runtimeCompose)
            // Ditto SDK
            implementation(libs.ditto)
            implementation(libs.okio)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
        jvmMain.dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.kotlinx.coroutinesSwing)
            // Ditto platform binaries for desktop
            implementation(libs.ditto.binaries)
        }
    }
}

// Ditto Secrets Configuration Generation
val generatedSources = layout.buildDirectory.dir("generated-sources")

val generateDittoSecrets by tasks.registering {
    val envFile = rootDir.resolve("../.env")
    val outputFile = generatedSources.map {
        it.file("com/edgestudio/config/DittoSecretsConfiguration.kt")
    }
    inputs.files(envFile.takeIf { it.exists() }).optional()
    outputs.file(outputFile)

    doLast {
        val properties = Properties()

        // Load properties from the .env file in parent directory
        if (envFile.exists()) {
            FileInputStream(envFile).use(properties::load)
        } else {
            throw FileNotFoundException("""
                Could not find .env file at ${envFile.path}.
                Please create a '.env' file in the root of the ditto-edge-studio repository based on the '.env-sample' file.
                Required properties: DITTO_APP_ID, DITTO_PLAYGROUND_TOKEN, DITTO_AUTH_URL, DITTO_WEBSOCKET_URL
            """.trimIndent())
        }

        val kotlinSource = """
            |package com.edgestudio.config
            |
            |/**
            | * Auto-generated configuration from .env file.
            | * Do not modify this file directly - edit the .env file instead.
            | */
            |object DittoSecretsConfiguration {
            |${properties.map { "    const val ${it.key}: String = \"${it.value.toString().removeSurrounding("\"")}\"" }.joinToString("\n")}
            |}
        """.trimMargin()

        outputFile.get().asFile.apply {
            parentFile.mkdirs()
            writeText(kotlinSource)
        }
    }
}

// Make Kotlin compilation depend on secret generation
tasks
    .withType<AbstractKotlinCompileTool<*>>()
    .configureEach {
        dependsOn(generateDittoSecrets)
    }

android {
    namespace = "com.edgestudio"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.edgestudio"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    debugImplementation(compose.uiTooling)
}

compose.desktop {
    application {
        mainClass = "com.edgestudio.MainKt"
        
        // JVM arguments for performance and macOS optimization
        jvmArgs += listOf(
            "-Dapple.awt.application.name=Ditto Edge Studio",
            // Performance optimizations for macOS
            "-Dskiko.fps.enabled=true",
            "-Dskiko.vsync.enabled=true",
            "-Dskiko.renderApi=METAL",
            // JVM performance tuning
            "-XX:+UseG1GC",
            "-XX:+UseStringDeduplication",
            "-Xmx2g",
            // Reduce resize lag
            "-Dawt.useSystemAAFontSettings=lcd",
            "-Dswing.aatext=true"
        )

        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
            packageName = "ditto-edge-studio"
            packageVersion = "1.0.0"
            
            macOS {
                bundleID = "com.edgestudio"
                
                // Entitlements configuration for macOS permissions
                entitlementsFile.set(project.file("entitlements.plist"))
                runtimeEntitlementsFile.set(project.file("runtime-entitlements.plist"))
                
                // Optional: minimum system version
                minimumSystemVersion = "12.0"
                
                // Optional: App name displayed in macOS
                dockName = "Ditto Edge Studio"
            }
            
            windows {
                // Windows-specific configuration
                menuGroup = "Ditto"
                perUserInstall = true
            }
            
            linux {
                // Linux-specific configuration
                menuGroup = "Development"
            }
        }
    }
}
