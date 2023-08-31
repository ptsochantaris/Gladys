import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct NotificationMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        let notificationName = node.argumentList.first!.expression.trimmedDescription
        let block = node.trailingClosure!
        let statements = block.statements.trimmedDescription
        let sig = block.signature?.firstToken(viewMode: .sourceAccurate)?.trimmedDescription ?? "_"
        return  """
                Task {
                    let iterator = NotificationCenter.default.notifications(named: \(raw: notificationName)).makeAsyncIterator()
                    while let \(raw: sig) = await iterator.next() {
                        let task = Task { \(raw: statements) }
                        guard await task.value else { return }
                    }
                }
                """
    }
}

@main
struct MinionsPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NotificationMacro.self
    ]
}
