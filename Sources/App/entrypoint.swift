import Dispatch

import GoogleCloudLogging
import Jobs
import Logging
import Vapor

let logger = Logger(label: "global")
typealias LogKey = GoogleCloudLogHandler.MetadataKey

/// This extension is temporary and can be removed once Vapor gets this support.
private extension Vapor.Application {
  static let baseExecutionQueue = DispatchQueue(label: "vapor.codes.entrypoint")

  func runFromAsyncMainEntrypoint() async throws {
    try await withCheckedThrowingContinuation { continuation in
      Vapor.Application.baseExecutionQueue.async { [self] in
        do {
          try self.run()
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

@main
enum Entrypoint {
  static func main() async throws {
    LoggingSystem.bootstrap {
      MultiplexLogHandler([
        GoogleCloudLogHandler(label: $0),
        StreamLogHandler.standardOutput(label: $0)
      ])
    }

    do {
      let serviceAccountCredentials = Bundle.module.url(forResource: "backend-logger", withExtension: "json")!
      try GoogleCloudLogHandler.setup(
        serviceAccountCredentials: serviceAccountCredentials,
        clientId: UUID()
      )
    } catch {
      print("Failed to set up Google Cloud Log handler")
    }

    let env = try Environment.detect()
    logger.info("Starting up backend service...")
    logger.info("Arguments: \(CommandLine.arguments)")
    logger.info("Environment: \(env)")

    let app = Application(env)
    defer { app.shutdown() }

    do {
      try await configure(app)
    } catch {
      app.logger.report(error: error)
      throw error
    }

    Jobs.add(interval: .seconds(15)) {
      GoogleCloudLogHandler.upload()
    }

    try await app.runFromAsyncMainEntrypoint()
  }
}
