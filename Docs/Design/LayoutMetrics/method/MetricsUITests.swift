// A UI-testing bundle in a throwaway Xcode project (product type com.apple.product-type.bundle.ui-testing,
// no host app), used only to rotate the simulator and tap through RecipeCodex while measuring.
// Run: TEST_RUNNER_METRICS_ACTION='landscapeLeft;sleep:2' xcodebuild test-without-building -xctestrun <file>
//      -destination 'platform=iOS Simulator,id=<udid>' -parallel-testing-enabled NO
// (without -parallel-testing-enabled NO, xcodebuild runs on a clone of the device and shuts the original down).
import XCTest

/// Drives the installed RecipeCodex for layout measurement. The action comes from the
/// METRICS_ACTION environment variable (passed as TEST_RUNNER_METRICS_ACTION to xcodebuild).
final class MetricsUITests: XCTestCase {
    func testAction() throws {
        let env = ProcessInfo.processInfo.environment
        let action = env["METRICS_ACTION"] ?? ""
        let app = XCUIApplication(bundleIdentifier: "com.calebpietrafesa.RecipeCodex")
        if app.state != .runningForeground { app.activate() }
        for step in action.split(separator: ";") {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "landscapeLeft": XCUIDevice.shared.orientation = .landscapeLeft
            case "landscapeRight": XCUIDevice.shared.orientation = .landscapeRight
            case "portrait": XCUIDevice.shared.orientation = .portrait
            case "tapButton": tapIfPresent(app.buttons[parts[1]].firstMatch, parts[1])
            case "tapText": tapIfPresent(app.staticTexts[parts[1]].firstMatch, parts[1])
            case "tapAny": tapIfPresent(app.descendants(matching: .any)[parts[1]].firstMatch, parts[1])
            case "tapPoint":
                let xy = parts[1].split(separator: ",").compactMap { Double($0) }
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            case "sleep": Thread.sleep(forTimeInterval: Double(parts[1]) ?? 1)
            case "tree": print("TREE-BEGIN\n\(app.debugDescription)\nTREE-END")
            default: break
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    /// Taps the element when it appears; otherwise logs it and carries on, so a run never fails.
    private func tapIfPresent(_ element: XCUIElement, _ name: String) {
        if element.waitForExistence(timeout: 3) { element.tap() } else { print("METRICS-MISSING \(name)") }
    }
}
