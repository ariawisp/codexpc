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

### Run the console sample

Build the framework and run the simple console sample that prints streamed deltas:

```
./gradlew :native:build   # or your configured target
kotlinc -script src/nativeMain/kotlin/com/yourorg/codexpc/SampleMain.kt  # or run from IDE
```

Alternatively, run a quick one‑off with `kotlinc` or your IDE by providing the checkpoint path and optional instructions:

```
CODEXPC_SERVICE=com.yourorg.codexpc \
  kotlin com.yourorg.codexpc.SampleMainKt \
  /path/to/model.bin "You are a helpful assistant."
```
