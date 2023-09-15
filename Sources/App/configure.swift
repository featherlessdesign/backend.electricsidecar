import Vapor

import APNS
import APNSCore
import VaporAPNS

private final class SelfBundleClass {

}

private struct ServerConfig: Codable {
  let apnsKeyIdentifier: String
  let apnsTeamIdentifier: String
}

// configures your application
public func configure(_ app: Application) async throws {
  // uncomment to serve files from /Public folder
  // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

  // register routes
  try routes(app)

  let p8FilePath = Bundle.module.url(forResource: "DevAuthKey", withExtension: "p8")!
  let apnsEnvironment: APNSEnvironment
  if ProcessInfo.processInfo.environment["APNS_ENVIRONMENT"] == "production" {
    apnsEnvironment = .production
  } else {
    apnsEnvironment = .sandbox
  }
  logger.info("Startup APNS environment: \(apnsEnvironment)")

  let serverConfigUrl = Bundle.module.url(forResource: "serverconfig", withExtension: "json")!
  let serverConfigData = try Data(contentsOf: serverConfigUrl)
  let serverConfig = try JSONDecoder().decode(ServerConfig.self, from: serverConfigData)

  let p8AsString = try! String(contentsOf: p8FilePath)

  // Configure APNS using JWT authentication.
  let apnsConfig = APNSClientConfiguration(
    authenticationMethod: .jwt(
      privateKey: try .loadFrom(string: p8AsString),
      keyIdentifier: serverConfig.apnsKeyIdentifier,
      teamIdentifier: serverConfig.apnsTeamIdentifier
    ),
    environment: apnsEnvironment
  )
  app.apns.containers.use(
    apnsConfig,
    eventLoopGroupProvider: .shared(app.eventLoopGroup),
    responseDecoder: JSONDecoder(),
    requestEncoder: JSONEncoder(),
    as: .default
  )
}
