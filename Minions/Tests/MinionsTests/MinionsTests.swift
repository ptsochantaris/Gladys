import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import MinionsMacros

let testMacros: [String: Macro.Type] = [
    "notifications": NotificationMacro.self
]

final class MinionsTests: XCTestCase {
    func testNotificationsMacro1() throws {
        assertMacroExpansion(
            """
            #notifications(for: .NAME) { notification in
                print(notification)
            }
            """,
            expandedSource:
            """
            Task {
                let iterator = NotificationCenter.default.notifications(named: .NAME).makeAsyncIterator()
                while let notification = await iterator.next() {
                    let task = Task {
                        print(notification)
                    }
                    guard await task.value else {
                        return
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    func testNotificationsMacro3() throws {
        assertMacroExpansion(
            """
            #notifications(for: .NAME) { _ in
                print("ok")
            }
            """,
            expandedSource:
            """
            Task {
                let iterator = NotificationCenter.default.notifications(named: .NAME).makeAsyncIterator()
                while let _ = await iterator.next() {
                    let task = Task {
                        print("ok")
                    }
                    guard await task.value else {
                        return
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    func testNotificationsMacro2() throws {
        assertMacroExpansion(
            """
            #notifications(for: .NAME) {
                print("ok")
            }
            """,
            expandedSource:
            """
            Task {
                let iterator = NotificationCenter.default.notifications(named: .NAME).makeAsyncIterator()
                while let _ = await iterator.next() {
                    let task = Task {
                        print("ok")
                    }
                    guard await task.value else {
                        return
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
}
