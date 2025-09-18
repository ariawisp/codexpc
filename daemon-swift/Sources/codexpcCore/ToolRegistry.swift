import Foundation
import XPC

final class ToolRegistry {
    struct Schema { let raw: [String: Any] }
    let schemas: [String: Schema]

    init(schemas: [String: Schema]) { self.schemas = schemas }

    static func fromXpcArray(_ x: xpc_object_t?) -> ToolRegistry? {
        guard let arr = x, xpc_get_type(arr) == XPC_TYPE_ARRAY else { return nil }
        var map: [String: Schema] = [:]
        _ = xpc_array_apply(arr) { (_, item) -> Bool in
            guard xpc_get_type(item) == XPC_TYPE_DICTIONARY else { return true }
            guard let n = xpc_dictionary_get_string(item, "name") else { return true }
            let name = String(cString: n)
            // Accept either inline JSON schema as string or nested object under key "json_schema"
            var schemaObj: Any? = nil
            if let sp = xpc_dictionary_get_string(item, "json_schema") {
                let s = String(cString: sp)
                if let data = s.data(using: .utf8) { schemaObj = try? JSONSerialization.jsonObject(with: data) }
            } else if let sch = xpc_dictionary_get_value(item, "json_schema"), xpc_get_type(sch) == XPC_TYPE_DICTIONARY {
                // Convert XPC dictionary to Data by building JSON manually
                if let json = ToolRegistry.xpcDictToJson(sch) { schemaObj = json }
            }
            if let dict = schemaObj as? [String: Any] {
                map[name] = Schema(raw: dict)
            }
            return true
        }
        if map.isEmpty { return nil }
        return ToolRegistry(schemas: map)
    }

    func validate(name: String, inputJson: String) -> (ok: Bool, error: String?) {
        guard let schema = schemas[name] else { return (false, "unknown tool: \(name)") }
        guard let data = inputJson.data(using: .utf8) else { return (false, "invalid utf-8") }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return (false, "invalid json") }
        return Self.validate(jsonObject: obj, schema: schema.raw)
    }

    // Build a conservative tools JSON payload. If Harmony rejects this shape,
    // the formatter will gracefully fallback to options without tools_json.
    var toolsJsonForHarmony: String? {
        var arr: [[String: Any]] = []
        for (name, schema) in schemas {
            let obj = schema.raw
            arr.append([
                "name": name,
                "json_schema": obj
            ])
        }
        let root: [String: Any] = ["tools": arr, "version": 1, "namespace": "functions"]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private static func validate(jsonObject: Any, schema: [String: Any]) -> (ok: Bool, error: String?) {
        if let t = schema["type"] as? String {
            switch t {
            case "object":
                guard let dict = jsonObject as? [String: Any] else { return (false, "expected object") }
                if let req = schema["required"] as? [String] {
                    for k in req { if dict[k] == nil { return (false, "missing required: \(k)") } }
                }
                if let props = schema["properties"] as? [String: Any] {
                    for (k, schVal) in props {
                        guard let sch = schVal as? [String: Any] else { continue }
                        if let v = dict[k] {
                            let res = validate(jsonObject: v, schema: sch)
                            if !res.ok { return (false, "invalid field \(k): \(res.error ?? "")") }
                        }
                    }
                    if let ap = schema["additionalProperties"] as? Bool, ap == false {
                        for k in dict.keys { if props[k] == nil { return (false, "unexpected field: \(k)") } }
                    }
                }
                return (true, nil)
            case "string":
                return ((jsonObject as? String) != nil ? (true, nil) : (false, "expected string"))
            case "integer":
                if jsonObject is Int { return (true, nil) }
                if let d = jsonObject as? Double, floor(d) == d { return (true, nil) }
                return (false, "expected integer")
            case "number":
                return ((jsonObject as? Double) != nil || (jsonObject as? Int) != nil) ? (true, nil) : (false, "expected number")
            case "boolean":
                return ((jsonObject as? Bool) != nil) ? (true, nil) : (false, "expected boolean")
            case "array":
                guard let arr = jsonObject as? [Any] else { return (false, "expected array") }
                if let itemSchema = schema["items"] as? [String: Any] {
                    for (i, v) in arr.enumerated() {
                        let res = validate(jsonObject: v, schema: itemSchema)
                        if !res.ok { return (false, "invalid item \(i): \(res.error ?? "")") }
                    }
                }
                return (true, nil)
            default:
                return (true, nil)
            }
        }
        // No explicit type → accept
        return (true, nil)
    }

    private static func xpcDictToJson(_ d: xpc_object_t) -> Any? {
        guard xpc_get_type(d) == XPC_TYPE_DICTIONARY else { return nil }
        var map: [String: Any] = [:]
        _ = xpc_dictionary_apply(d) { (k, v) -> Bool in
            let key = String(cString: k)
            if xpc_get_type(v) == XPC_TYPE_STRING, let p = xpc_string_get_string_ptr(v) {
                map[key] = String(cString: p)
            } else if xpc_get_type(v) == XPC_TYPE_BOOL {
                map[key] = xpc_bool_get_value(v)
            } else if xpc_get_type(v) == XPC_TYPE_INT64 {
                map[key] = Int(xpc_int64_get_value(v))
            } else if xpc_get_type(v) == XPC_TYPE_DOUBLE {
                map[key] = xpc_double_get_value(v)
            } else if xpc_get_type(v) == XPC_TYPE_DICTIONARY {
                map[key] = xpcDictToJson(v) ?? [:]
            } else if xpc_get_type(v) == XPC_TYPE_ARRAY {
                map[key] = xpcArrayToJson(v)
            }
            return true
        }
        return map
    }

    private static func xpcArrayToJson(_ a: xpc_object_t) -> [Any] {
        var arr: [Any] = []
        _ = xpc_array_apply(a) { (_, v) -> Bool in
            if xpc_get_type(v) == XPC_TYPE_STRING, let p = xpc_string_get_string_ptr(v) {
                arr.append(String(cString: p))
            } else if xpc_get_type(v) == XPC_TYPE_BOOL {
                arr.append(xpc_bool_get_value(v))
            } else if xpc_get_type(v) == XPC_TYPE_INT64 {
                arr.append(Int(xpc_int64_get_value(v)))
            } else if xpc_get_type(v) == XPC_TYPE_DOUBLE {
                arr.append(xpc_double_get_value(v))
            } else if xpc_get_type(v) == XPC_TYPE_DICTIONARY {
                arr.append(xpcDictToJson(v) ?? [:])
            } else if xpc_get_type(v) == XPC_TYPE_ARRAY {
                arr.append(xpcArrayToJson(v))
            }
            return true
        }
        return arr
    }
}
