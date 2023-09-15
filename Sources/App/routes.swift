import GoogleCloudLogging
import Vapor

func routes(_ app: Application) throws {
  try app.register(collection: LiveActivitiesController())

  app.get("ping") { req async -> String in
    req.logger.info("pong")
    GoogleCloudLogHandler.upload()
    return "pong"
  }

  app.get("healthz") { req async -> String in
    return "OK"
  }
}
