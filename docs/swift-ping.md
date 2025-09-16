# Swift ping example

Drop this into a scratch Swift file to ping the service while building the Kotlin/Native client.

```
import Foundation
import XPC

let svc = "com.yourorg.codexpc"
let conn = xpc_connection_create_mach_service(svc, nil, 0)
xpc_connection_set_event_handler(conn) { ev in
  guard let ev = ev else { return }
  if xpc_get_type(ev) == XPC_TYPE_DICTIONARY {
    if let typ = xpc_dictionary_get_string(ev, "type") {
      print("event type: \(String(cString: typ))")
    }
  }
}
xpc_connection_resume(conn)

let msg = xpc_dictionary_create(nil, nil, 0)
xpc_dictionary_set_string(msg, "service", svc)
xpc_dictionary_set_uint64(msg, "proto_version", 1)
xpc_dictionary_set_string(msg, "type", "create")
xpc_dictionary_set_string(msg, "req_id", UUID().uuidString)
xpc_dictionary_set_string(msg, "model", "gpt-oss-20b")
xpc_dictionary_set_string(msg, "checkpoint_path", "/tmp/model.bin")
xpc_dictionary_set_string(msg, "instructions", "Hello")
xpc_connection_send_message(conn, msg)

RunLoop.current.run()
```

