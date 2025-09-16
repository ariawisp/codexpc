# Kotlin/Native Client

This library talks to the `codexpc` daemon via libxpc and exposes a simple API for streaming events.

## Structure

- `src/nativeMain/kotlin/` — client API
- `src/nativeInterop/cinterop/xpc.def` — cinterop config for libxpc

## Build

Use Gradle with Kotlin/Native configured for `macosArm64`. Example `build.gradle.kts` is provided as a starting point.

## Sample

```
val client = CodexpcClient("com.yourorg.codexpc")
client.start(Request(...)).collect { ev -> println(ev) }
```

