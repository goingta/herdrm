import XCTest
@testable import HerdrMobile

@MainActor
final class GatewayConfigurationTests: XCTestCase {
    func testLegacyProfilesStayDirectAndIPv6GatewaysAreAccepted() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Data("""
        {"version":1,"devices":[{"id":"F909464B-03C9-4944-8C53-088D7A571112","name":"Legacy","host":"dev.example","username":"alice"}]}
        """.utf8), forKey: "devices.v1")
        let store = MobileDeviceStore(defaults: defaults)
        let legacy = try XCTUnwrap(store.load().first)
        XCTAssertEqual(legacy.sshRoute, .direct)
        var ipv6 = legacy
        ipv6.sshRoute = .httpConnect
        ipv6.gatewayHost = "::1"
        XCTAssertEqual(try ipv6.validated().gatewayHost, "::1")
    }

    func testGatewayRejectionDescribesStatusInSelectedLanguage() {
        let previous = AppLanguagePreference.shared.selection
        defer { AppLanguagePreference.shared.selection = previous }
        AppLanguagePreference.shared.selection = .simplifiedChinese
        XCTAssertEqual(MobileTransportError.gatewayRejected(status: 403).errorDescription,
                       "HTTP CONNECT 网关拒绝建立隧道（HTTP 403）。请检查 SSH 主机和网关访问策略。")
    }

    func testInvalidGatewayCannotReplaceSavedRoute() throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let original = MobileDevice(name: "Daily", host: "dev.example", username: "alice")
        store.save([original])
        let model = MobileAppModel(store: store)
        var invalid = original
        invalid.sshRoute = .httpConnect
        for host in ["", "https://gateway.example", "gateway.example:8080", "gateway\r\nInjected: yes"] {
            invalid.gatewayHost = host
            XCTAssertThrowsError(try model.updateDevice(invalid), "Invalid gateway: \(host)")
        }
        invalid.gatewayHost = "gateway.example"
        invalid.gatewayPort = 0
        XCTAssertThrowsError(try model.updateDevice(invalid))
        XCTAssertEqual(MobileAppModel(store: store).devices, [original])
    }

    func testGatewayRouteCanBeEditedAndSurvivesRestart() throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Daily", host: "dev.example", username: "alice")
        store.save([device])
        let model = MobileAppModel(store: store, connector: { _ in throw CancellationError() })
        var edited = device
        edited.sshRoute = .httpConnect
        edited.gatewayHost = " gateway.example "
        edited.gatewayPort = 32083
        try model.updateDevice(edited)
        let restarted = MobileAppModel(store: store)
        XCTAssertEqual(restarted.devices.first?.sshRoute, .httpConnect)
        XCTAssertEqual(restarted.devices.first?.gatewayHost, "gateway.example")
        XCTAssertEqual(restarted.devices.first?.gatewayPort, 32083)
        edited.sshRoute = .direct
        try model.updateDevice(edited)
        XCTAssertEqual(MobileAppModel(store: store).devices.first?.sshRoute, .direct)
    }
}
