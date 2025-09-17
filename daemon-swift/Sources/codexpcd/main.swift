import Foundation
import codexpcCore

@main
struct Main {
    static func main() {
        var serviceName = "com.yourorg.codexpc"
        // Simple arg parsing for --service override and optional --foreground flag (no-op)
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--service": serviceName = it.next() ?? serviceName
            case "--foreground": _ = true // accepted for compatibility
            default: break
            }
        }
        let server = XpcServer(serviceName: serviceName)
        server.run()
    }
}
