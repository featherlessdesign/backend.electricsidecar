import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

import GarageModel
import Preferences

struct ChargingActivityContentStateV1: Codable, Hashable {
  init(readout: GarageModel.Vehicle.ReadoutV1) {
    self.readout = readout
  }

  let readout: GarageModel.Vehicle.ReadoutV1
}

extension GarageModel.Vehicle {
  enum ReadoutV1: Codable, Hashable {
    init(v2: GarageModel.Vehicle.Readout) {
      switch v2 {
      case .ev(let electricReadout):
        self = .ev(.init(
          batteryLevel: electricReadout.batteryLevel,
          isCharging: electricReadout.state == .charging,
          isPluggedIn: electricReadout.state == .pluggedIn,
          chargeRateInKmPerHour: electricReadout.chargeRateInKmPerHour,
          chargeRateInKW: electricReadout.chargeRateInKW
        ))
      case .phev(let electricReadout, let conventionalReadout):
        self = .phev(
          .init(
            batteryLevel: electricReadout.batteryLevel,
            isCharging: electricReadout.state == .charging,
            isPluggedIn: electricReadout.state == .pluggedIn,
            chargeRateInKmPerHour: electricReadout.chargeRateInKmPerHour,
            chargeRateInKW: electricReadout.chargeRateInKW
          ),
          .init(fuelLevel: conventionalReadout.fuelLevel)
        )
      case .conventional(let conventionalReadout):
        self = .conventional(.init(fuelLevel: conventionalReadout.fuelLevel))
      case .unknown:
        self = .unknown
      }
    }

    struct ElectricReadout: Codable, Hashable {
      init(batteryLevel: Double, isCharging: Bool, isPluggedIn: Bool, chargeRateInKmPerHour: Double, chargeRateInKW: Double) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.chargeRateInKmPerHour = chargeRateInKmPerHour
        self.chargeRateInKW = chargeRateInKW
      }

      let batteryLevel: Double
      let isCharging: Bool
      let isPluggedIn: Bool
      let chargeRateInKmPerHour: Double
      let chargeRateInKW: Double
    }

    struct ConventionalReadout: Codable, Hashable {
      init(fuelLevel: Double) {
        self.fuelLevel = fuelLevel
      }
      let fuelLevel: Double
    }
    case ev(ElectricReadout)
    case phev(ElectricReadout, ConventionalReadout)
    case conventional(ConventionalReadout)
    case unknown
  }
}
