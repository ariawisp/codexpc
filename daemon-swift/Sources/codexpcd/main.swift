import Foundation
import codexpcCore

@main
struct Main {
    static func main() {
        let server = XpcServer(serviceName: "com.yourorg.codexpc")
        server.run()
    }
}

