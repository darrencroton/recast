import XCTest
@testable import Recast

@MainActor
final class AppLifecycleControllerTests: XCTestCase {

    func test_handleMainWindowPresentation_runsLaunchTasksOnce() {
        var launchCount = 0
        var activationCount = 0
        let controller = AppLifecycleController(
            launchHandler: {
                launchCount += 1
            },
            runtime: makeRuntime(
                activateApp: {
                    activationCount += 1
                }
            )
        )

        controller.handleMainWindowPresentation()
        controller.handleMainWindowPresentation()

        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func test_openRecast_reopensWindowAndActivatesApp() {
        var didOpenWindow = false
        var activationCount = 0
        let controller = AppLifecycleController(
            launchHandler: {},
            runtime: makeRuntime(
                activateApp: {
                    activationCount += 1
                }
            )
        )

        controller.openRecast {
            didOpenWindow = true
        }

        XCTAssertTrue(didOpenWindow)
        XCTAssertEqual(activationCount, 1)
    }

    func test_quitRecast_terminatesApp() {
        var didTerminate = false
        let controller = AppLifecycleController(
            launchHandler: {},
            runtime: makeRuntime(
                terminate: {
                    didTerminate = true
                }
            )
        )

        controller.quitRecast()

        XCTAssertTrue(didTerminate)
    }

    private func makeRuntime(
        activateApp: @escaping () -> Void = {},
        terminate: @escaping () -> Void = {}
    ) -> AppLifecycleRuntime {
        AppLifecycleRuntime(
            activateApp: activateApp,
            terminate: terminate
        )
    }
}
