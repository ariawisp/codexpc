plugins {
    kotlin("multiplatform") version "2.0.0"
}

kotlin {
    macosArm64("native") {
        binaries {
            framework {
                baseName = "codexpcclient"
            }
        }
        compilations.getByName("main") {
            cinterops.create("xpc") {
                defFile(project.file("src/nativeInterop/cinterop/xpc.def"))
            }
        }
    }

    sourceSets {
        val nativeMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
            }
        }
        val nativeTest by getting
    }
}
