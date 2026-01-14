@testable import InstaxKit
import Testing

struct DetectionTests {
  @Test func detectSP1FromModelName() throws {
    let modelNames = ["SP-1", "sp-1", "SP1", "Instax SP-1"]

    for name in modelNames {
      let upper = name.uppercased()
      let isSP1 = upper.contains("SP-1") || upper.contains("SP1")
      #expect(isSP1 == true)
    }
  }

  @Test func detectSP2FromModelName() throws {
    let modelNames = ["SP-2", "sp-2", "SP2", "Instax SP-2"]

    for name in modelNames {
      let upper = name.uppercased()
      let isSP2 = upper.contains("SP-2") || upper.contains("SP2")
      #expect(isSP2 == true)
    }
  }

  @Test func detectSP3FromModelName() throws {
    let modelNames = ["SP-3", "sp-3", "SP3", "Instax SP-3"]

    for name in modelNames {
      let upper = name.uppercased()
      let isSP3 = upper.contains("SP-3") || upper.contains("SP3")
      #expect(isSP3 == true)
    }
  }

  @Test func printerDetectionErrorDescription() {
    let error = PrinterDetectionError.unknownModel("SP-0")
    #expect(error.description == "Unknown printer model: SP-0. Expected SP-1, SP-2, or SP-3.")
  }
}
