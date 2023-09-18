import MinionsMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

let testMacros: [String: Macro.Type] = [
    "notifications": NotificationMacro.self
]

final class MinionsTests: XCTestCase {
    func testNotificationsMacro1() throws {
        assertMacroExpansion(
            """
            notifications(for: .NAME) { notification in
                print(notification)
            }
            """,
            expandedSource:
            """
            Task {
                for await notification in NotificationCenter.default.notifications(named: .NAME) {
                    print(notification)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testNotificationsMacro3() throws {
        assertMacroExpansion(
            """
            notifications(for: .NAME) { _ in
                print("ok")
            }
            """,
            expandedSource:
            """
            Task {
                for await notification in NotificationCenter.default.notifications(named: .NAME) {
                    print("ok")
                }
            }
            """,
            macros: testMacros
        )
    }

    func testNotificationsMacro2() throws {
        assertMacroExpansion(
            """
            notifications(for: .NAME) {
                print("ok")
            }
            """,
            expandedSource:
            """
            Task {
                for await notification in NotificationCenter.default.notifications(named: .NAME) {
                    print("ok")
                }
            }
            """,
            macros: testMacros
        )
    }
}
