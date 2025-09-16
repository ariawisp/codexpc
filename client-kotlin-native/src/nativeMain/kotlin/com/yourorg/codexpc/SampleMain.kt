package com.yourorg.codexpc

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.collect

// Simple console sample that streams a single request and prints deltas.
fun main(args: Array<String>) = runBlocking {
    val service = System.getenv("CODEXPC_SERVICE") ?: "com.yourorg.codexpc"
    val checkpoint = args.getOrNull(0) ?: run {
        System.err.println("usage: SampleMain <checkpoint_path> [instructions]")
        return@runBlocking
    }
    val instructions = args.getOrNull(1) ?: "Hello from Kotlin client"
    val client = CodexpcClient(service)
    val req = Request(
        reqId = java.util.UUID.randomUUID().toString(),
        model = "gpt-oss",
        checkpointPath = checkpoint,
        instructions = instructions,
    )
    val h = client.startWithHandle(req)
    try {
        h.flow.collect { ev ->
            when (ev) {
                is Event.Created -> println("[created]")
                is Event.OutputTextDelta -> print(ev.text)
                is Event.Completed -> println("\n[completed] id=${ev.responseId}")
                is Event.Error -> {
                    System.err.println("error: ${ev.code}: ${ev.message}")
                }
            }
        }
    } finally {
        // best-effort cancel if still running
        h.cancel()
    }
}

