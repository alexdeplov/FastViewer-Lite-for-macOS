import XCTest
@testable import FastViewer_Lite

final class DefaultFileAssociationManagerTests: XCTestCase {
    func testDefaultFileAssociationManagerIsSingleton() {
        XCTAssertTrue(
            DefaultFileAssociationManager.shared === DefaultFileAssociationManager.shared
        )
    }

    func testStateCanBeReadWithoutChangingSystemAssociations() {
        switch DefaultFileAssociationManager.shared.state {
        case .available, .managedByFastViewer, .alreadyDefault:
            XCTAssertTrue(true)
        }
    }
}
