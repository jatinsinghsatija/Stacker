group = "com.stacker.stacker"

// The published artifact version.
//
// `flutter build aar` overrides this with the value in the generated
// .android/Flutter/build.gradle, so scripts/jitpack_build.sh stamps that file
// from the git tag. This value is only what a direct Gradle build produces.
version = "0.2.0"

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

// Keep the Kotlin stdlib out of the published dependency graph.
//
// The Flutter toolchain pins the Kotlin plugin version, so the stdlib the
// plugin adds automatically is whatever Flutter ships (2.3.20 today). Left
// alone, the published POM hard-requires that version and drags every
// consumer's stdlib forward — apps on an older Kotlin plugin then fail to
// compile with "Module was compiled with an incompatible version of Kotlin".
// Verified against a real consumer app on Kotlin 2.0.21.
//
// Downgrading to `compileOnly` is safe: every Android app that can use a
// Kotlin library already has a stdlib on its runtime classpath, so Stacker
// never needs to supply one.
configurations.configureEach {
    if (name.endsWith("RuntimeElements") || name.endsWith("ApiElements")) {
        withDependencies {
            removeIf {
                it.group == "org.jetbrains.kotlin" &&
                    it.name.startsWith("kotlin-stdlib")
            }
        }
    }
}

android {
    namespace = "com.stacker.stacker"

    // Deliberately 35 rather than the newest SDK. `compileSdk` propagates to
    // consumers: publishing against 36 forces every app that adds Stacker
    // onto AGP 8.9+, which is an absurd upgrade to demand for a debug tool.
    // Nothing here uses an API above 35.
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17

        // Emit Kotlin 1.9 metadata rather than the compiler's own 2.3 format.
        //
        // Without this, the published AAR carries metadata version 2.3.0 and
        // any consumer on an older Kotlin plugin fails to compile with
        // "Module was compiled with an incompatible version of Kotlin".
        // Verified against a real consumer app: Kotlin 2.0.21 could not read
        // the 2.3-metadata AAR at all.
        //
        // 1.9 is chosen as the floor because it covers every Kotlin release
        // in current use while still allowing the library's own source to use
        // modern idioms the 1.9 language level already supports.
        apiVersion = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9
        languageVersion = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9
    }
}

dependencies {
    // OkHttp is compileOnly on purpose: StackerOkHttpInterceptor is only
    // referenced by apps that already use OkHttp (directly or via Retrofit),
    // and those apps bring their own version. Making it `implementation` would
    // force OkHttp into apps that use HttpURLConnection or Ktor and would risk
    // clashing with the host's chosen version.
    compileOnly("com.squareup.okhttp3:okhttp:4.12.0")

    // Pin the stdlib rather than letting the Kotlin plugin inject its own
    // version. The Flutter toolchain builds this module with Kotlin 2.3.x,
    // which would otherwise publish a hard `kotlin-stdlib:2.3.20` dependency
    // and drag every consumer's stdlib forward — apps on an older Kotlin
    // plugin then fail with "Module was compiled with an incompatible version
    // of Kotlin". Verified against a real consumer app on Kotlin 2.0.21.
    //
    // 1.9.24 is a floor, not a ceiling: Gradle resolves to the highest
    // requested version, so an app already on a newer stdlib keeps it.
    compileOnly("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
