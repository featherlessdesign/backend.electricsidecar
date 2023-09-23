import Foundation

import APNS
import APNSCore
import Jobs
import Vapor
import VaporAPNS

import Activities
import BackendAPI
import GarageModel
import GoogleCloudLogging
import NetworkClient
import PorscheAPI
import PorscheDataModel
import PorscheDataModelTranslator

final class RegisteredLiveActivity {
  init(registration: LiveActivityRegistration, job: Job) {
    self.registration = registration
    self.job = job
  }

  let registration: LiveActivityRegistration
  let job: Job

  var lastUpdate: Date?
  var lastReadout: GarageModel.Vehicle.Readout?
  var porscheCapabilities: Capabilities?
}

private var activities: [String: RegisteredLiveActivity] = [:]
private let networkClient = NetworkClient()
private let porscheEndpoints = PorscheAPIEndpoints()

private let fastChargeInterval = (60)
private let slowChargeInterval = (60 * 2 + 30)

struct LiveActivitiesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.post("start_charging", use: startCharging)
    routes.post("dismiss_charging", use: dismissCharging)
    routes.get("active_activities", use: activeActivities)
  }

  private func activeActivities(req: Request) async throws -> String {
    return "\(activities.count)"
  }

  private func startCharging(req: Request) async throws -> String {
    guard let data = req.body.data else {
      return "no data"
    }
    let decoder = JSONDecoder()
    do {
      let registration = try decoder.decode(LiveActivityRegistration.self, from: data)

      try await terminateLiveActivity(req: req, identifier: registration.identifier)

      req.logger.info("Scheduling timer for live activity \(registration.pushToken)")

      var job: Job?
      job = Jobs.add(interval: slowChargeInterval.seconds, autoStart: false) {
        Task {
          do {
            try await updateLiveActivity(req: req, registration: registration, app: req.application)
          } catch let error {
            req.logger.error("Failed to update live activity", metadata: [LogKey.error: "\(error)"])
            try await terminateLiveActivity(req: req, identifier: registration.identifier)
          }
        }
      } onError: { error in
        return .none
      }
      guard let job else {
        return "failed to register"
      }

      let activity = RegisteredLiveActivity(
        registration: registration,
        job: job
      )
      activities[registration.identifier] = activity

      // Prime the activity.
      try await updateLiveActivity(req: req, registration: registration, app: req.application)

      job.start()

    } catch let error {
      req.logger.error("Failed to schedule live activity", metadata: [LogKey.error: "\(error)"])
      return "failed"
    }
    return ""
  }

  private func dismissCharging(req: Request) async throws -> String {
    guard let data = req.body.data else {
      return "no data"
    }
    let decoder = JSONDecoder()
    do {
      let termination = try decoder.decode(LiveActivityTermination.self, from: data)
      req.logger.info("Stopping live activity due to dismissal")
      try await terminateLiveActivity(req: req, identifier: termination.identifier)

    } catch let error {
      req.logger.error("Failed to dismiss live activity", metadata: [LogKey.error: "\(error)"])
      return "failed"
    }
    return ""
  }

  private func terminateLiveActivity(req: Request, identifier: String) async throws {
    guard let activity = activities[identifier] else {
      req.logger.warning("No activity found")
      return
    }

    activity.job.stop()
    activities.removeValue(forKey: identifier)
  }

  private func updateLiveActivity(req: Request, registration: LiveActivityRegistration, app: Application) async throws {
    guard let activity = activities[registration.identifier] else {
      req.logger.warning("No activity found")
      return
    }

    if let lastUpdate = activity.lastUpdate, Date.now.timeIntervalSince(lastUpdate) < 50 {
      // We already updated within the last minute, skip this excessive check.
      req.logger.info("Skipping update")
      return
    }

    let readout: GarageModel.Vehicle.Readout

    req.logger.info("Updating live activity for \(registration.pushToken)")

    switch registration.dataSource {
    case .porsche:
      let headers = [
        "Authorization": "Bearer \(registration.authToken.accessToken)",
        "x-vrs-url-country": registration.localeEnvironment.countryCode,
        "x-vrs-url-language": registration.localeEnvironment.identifier,
      ]
      let capabilities: Capabilities
      if let cachedCapabilities = activity.porscheCapabilities {
        capabilities = cachedCapabilities
      } else {
        guard let capabilitiesData = try await networkClient.get(
          url: porscheEndpoints.capabilitiesURL(vin: registration.vin),
          headers: headers
        ) else {
          return
        }
        capabilities = try JSONDecoder().decode(Capabilities.self, from: capabilitiesData)
        activity.porscheCapabilities = capabilities
      }

      let statusURL = porscheEndpoints.statusURL(
        countryCode: registration.localeEnvironment.countryCode,
        localeCode: registration.localeEnvironment.identifier,
        capabilities: capabilities,
        vin: registration.vin
      )
      guard let statusData = try await networkClient.get(url: statusURL, headers: headers) else {
        return
      }
      let emobility = try JSONDecoder().decode(Emobility.self, from: statusData)
      let status = GarageModel.Vehicle.Status(emobility: emobility, lastModified: .now)

      readout = status.readout

    case .simulated:
      readout = GarageModel.Vehicle.Readout.ev(
        .init(
          batteryLevel: 25,
          state: .charging,
          chargeRateInKmPerHour: 10,
          chargeRateInKW: 4
        )
      )
    case .tesla:
      return
    }

    if activity.lastReadout == readout {
      req.logger.info("Skipping APNS due to lack of change for \(registration.pushToken)")
      // Skip update because nothing's changed since the last time.
      return
    }

    req.logger.info("Sending APNS update \(readout) to \(registration.pushToken)")

    let event: APNSLiveActivityNotificationEvent = readout.state == .charging ? .update : .end

    switch registration.version {
    case .v2:
      let notification = APNSLiveActivityNotification(
        expiration: .immediately,
        priority: .consideringDevicePower,
        appID: "com.featherless.apps.electricsidecar",
        contentState: ChargingActivityContentState(readout: readout),
        event: event,
        timestamp: Int(Date.now.timeIntervalSince1970),
        dismissalDate: .date(.now.addingTimeInterval(60 * 5))
      )
      try await app.apns.client.sendLiveActivityNotification(notification, deviceToken: registration.pushToken)

    case .v1: fallthrough
    default:
      let notification = APNSLiveActivityNotification(
        expiration: .immediately,
        priority: .consideringDevicePower,
        appID: "com.featherless.apps.electricsidecar",
        contentState: ChargingActivityContentStateV1(readout: .init(v2: readout)),
        event: event,
        timestamp: Int(Date.now.timeIntervalSince1970),
        dismissalDate: .date(.now.addingTimeInterval(60 * 5))
      )
      try await app.apns.client.sendLiveActivityNotification(notification, deviceToken: registration.pushToken)
    }

    if let chargeRateInKW = readout.electricReadout?.chargeRateInKW {
      if chargeRateInKW > 100 {
        activity.job.interval = fastChargeInterval.seconds.unixTime
      } else {
        activity.job.interval = slowChargeInterval.seconds.unixTime
      }
    }

    activity.lastReadout = readout
    activity.lastUpdate = .now

    if readout.state != .charging {
      req.logger.info("Charging completed. Terminating live update.")
      try await terminateLiveActivity(req: req, identifier: registration.identifier)
    }
  }
}
