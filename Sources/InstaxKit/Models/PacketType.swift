/// Message types for Instax protocol communication.
public enum PacketType: UInt8, Sendable {
  case specifications = 79
  case reset = 80
  case prepImage = 81
  case sendImage = 82
  case type83 = 83
  case setLockState = 176
  case lockDevice = 179
  case changePassword = 182
  case printerVersion = 192
  case printCount = 193
  case modelName = 194
  case type195 = 195
  case prePrint = 196
}

/// Message mode indicating direction of communication.
public enum PacketMode: UInt8, Sendable {
  case command = 36 // Client to Printer
  case response = 42 // Printer to Client
}

/// Response codes from the printer.
public enum ResponseCode: UInt8, Sendable, CustomStringConvertible {
  case ready = 0x00 // RTN_E_RCV_FRAME - Ready/Print Complete
  case stUpdate = 0x7F // RET_HOLD
  case otherUsed = 0xA0 // RTN_E_OTHER_USED
  case notImageData = 0xA1 // RTN_E_NOT_IMAGE_DATA
  case batteryEmpty = 0xA2 // RTN_E_BATTERY_EMPTY
  case printing = 0xA3 // RTN_E_PRINTING / ST_PRINT
  case ejecting = 0xA4 // RTN_E_EJECTING
  case testing = 0xA5 // RTN_E_TESTING
  case charging = 0xB4 // RTN_E_CHARGE
  case connectError = 0xE0 // RTN_E_CONNECT
  case recvFrame4 = 0xF0 // RTN_E_RCV_FRAME_4
  case recvFrame3 = 0xF1 // RTN_E_RCV_FRAME_3
  case recvFrame2 = 0xF2 // RTN_E_RCV_FRAME_2
  case recvFrame1 = 0xF3 // RTN_E_RCV_FRAME_1
  case filmEmpty = 0xF4 // RTN_E_FILM_EMPTY
  case camPoint = 0xF5 // RTN_E_CAM_POINT
  case motor = 0xF6 // RTN_E_MOTOR
  case unmatchPass = 0xF7 // RTN_E_UNMATCH_PASS
  case piSensor = 0xF8 // RTN_E_PI_SENSOR

  case unknown = 0xFF

  public init(rawValue: UInt8) {
    switch rawValue {
    case 0x00: self = .ready
    case 0x7F: self = .stUpdate
    case 0xA0: self = .otherUsed
    case 0xA1: self = .notImageData
    case 0xA2: self = .batteryEmpty
    case 0xA3: self = .printing
    case 0xA4: self = .ejecting
    case 0xA5: self = .testing
    case 0xB4: self = .charging
    case 0xE0: self = .connectError
    case 0xF0: self = .recvFrame4
    case 0xF1: self = .recvFrame3
    case 0xF2: self = .recvFrame2
    case 0xF3: self = .recvFrame1
    case 0xF4: self = .filmEmpty
    case 0xF5: self = .camPoint
    case 0xF6: self = .motor
    case 0xF7: self = .unmatchPass
    case 0xF8: self = .piSensor
    default: self = .unknown
    }
  }

  public var description: String {
    switch self {
    case .ready: "Ready"
    case .stUpdate: "Update"
    case .otherUsed: "Other Used"
    case .notImageData: "Not Image Data"
    case .batteryEmpty: "Battery Empty"
    case .printing: "Printing"
    case .ejecting: "Ejecting"
    case .testing: "Testing"
    case .charging: "Charging"
    case .connectError: "Connection Error"
    case .recvFrame4, .recvFrame3, .recvFrame2, .recvFrame1: "Receive Frame Error"
    case .filmEmpty: "Film Empty"
    case .camPoint: "Cam Point Error"
    case .motor: "Motor Error"
    case .unmatchPass: "Wrong Password"
    case .piSensor: "PI Sensor Error"
    case .unknown: "Unknown"
    }
  }

  public var isError: Bool {
    switch self {
    case .ready, .printing, .ejecting, .testing, .charging, .stUpdate:
      false
    default:
      true
    }
  }
}
