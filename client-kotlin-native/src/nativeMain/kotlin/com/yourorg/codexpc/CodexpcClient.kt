package com.yourorg.codexpc

import kotlinx.cinterop.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import platform.posix.*
import xpc.*

data class Request(
    val reqId: String,
    val model: String,
    val checkpointPath: String,
    val instructions: String,
)

sealed interface Event {
    data class Created(val features: List<String> = emptyList()) : Event
    data class OutputTextDelta(val text: String) : Event
    data class Completed(val responseId: String) : Event
    data class Error(val code: String, val message: String) : Event
}

class CodexpcClient(private val serviceName: String) {
    data class StartHandle(val flow: Flow<Event>, val cancel: () -> Unit)

    fun startWithHandle(req: Request): StartHandle {
        var connRef: xpc_connection_t? = null
        val f = startInternal(req) { conn -> connRef = conn }
        val cancelFun = {
            val c = connRef
            if (c != null) {
                memScoped {
                    val cancel = xpc_dictionary_create(null, null, 0u)
                    xpc_dictionary_set_string(cancel, "service", serviceName)
                    xpc_dictionary_set_uint64(cancel, "proto_version", 1u)
                    xpc_dictionary_set_string(cancel, "type", "cancel")
                    xpc_dictionary_set_string(cancel, "req_id", req.reqId)
                    xpc_connection_send_message(c, cancel)
                }
            }
        }
        return StartHandle(f) { cancelFun() }
    }

    fun start(req: Request): Flow<Event> = startInternal(req) { _ -> }

    private fun startInternal(req: Request, onConnected: (xpc_connection_t?) -> Unit): Flow<Event> = callbackFlow {
        var conn: xpc_connection_t? = null
        memScoped {
            conn = xpc_connection_create_mach_service(serviceName, null, 0u)
            // expose to outer
            onConnected(conn)
            val c = conn!!
            xpc_connection_set_event_handler(c) { ev ->
                if (ev == null) return@xpc_connection_set_event_handler
                val type = xpc_get_type(ev)
                if (type == XPC_TYPE_DICTIONARY) {
                    val rid = xpc_dictionary_get_string(ev, "req_id")?.toKString()
                    if (rid != null && rid != req.reqId) return@xpc_connection_set_event_handler
                    when (xpc_dictionary_get_string(ev, "type")?.toKString() ?: "") {
                        "created" -> trySend(Event.Created())
                        "output_text.delta" -> trySend(Event.OutputTextDelta(xpc_dictionary_get_string(ev, "text")?.toKString() ?: ""))
                        "completed" -> trySend(Event.Completed(xpc_dictionary_get_string(ev, "response_id")?.toKString() ?: ""))
                        "error" -> trySend(
                            Event.Error(
                                xpc_dictionary_get_string(ev, "code")?.toKString() ?: "",
                                xpc_dictionary_get_string(ev, "message")?.toKString() ?: ""
                            )
                        )
                    }
                }
            }
            xpc_connection_resume(c)

            val msg = xpc_dictionary_create(null, null, 0u)
            xpc_dictionary_set_string(msg, "service", serviceName)
            xpc_dictionary_set_uint64(msg, "proto_version", 1u)
            xpc_dictionary_set_string(msg, "type", "create")
            xpc_dictionary_set_string(msg, "req_id", req.reqId)
            xpc_dictionary_set_string(msg, "model", req.model)
            xpc_dictionary_set_string(msg, "checkpoint_path", req.checkpointPath)
            xpc_dictionary_set_string(msg, "instructions", req.instructions)
            xpc_connection_send_message(c, msg)
        }
        awaitClose {
            val c = conn
            if (c != null) {
                val cancel = xpc_dictionary_create(null, null, 0u)
                xpc_dictionary_set_string(cancel, "service", serviceName)
                xpc_dictionary_set_uint64(cancel, "proto_version", 1u)
                xpc_dictionary_set_string(cancel, "type", "cancel")
                xpc_dictionary_set_string(cancel, "req_id", req.reqId)
                xpc_connection_send_message(c, cancel)
            }
        }
    }
}
