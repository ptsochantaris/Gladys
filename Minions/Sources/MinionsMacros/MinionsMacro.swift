import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct NotificationMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in _: some MacroExpansionContext) throws -> ExprSyntax {
        let notificationName = node.argumentList.first!.expression.trimmedDescription
        let block = node.trailingClosure!
        let statements = block.statements.trimmedDescription
        let sig = block.signature?.firstToken(viewMode: .sourceAccurate)?.trimmedDescription ?? "_"
        return """
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

public struct WithWeakSelfMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in _: some MacroExpansionContext) throws -> ExprSyntax {
        let block = node.trailingClosure!

        var statements = CodeBlockItemListSyntax(stringLiteral: "guard let self else { return }")
        statements.append(contentsOf: block.statements)

        if let sig = block.signature?.tokens(viewMode: .fixedUp).map(\.trimmedDescription).joined(separator: " ") {
            return "{ [weak self] \(raw: sig) \(raw: statements.trimmedDescription) }"
        } else {
            return "{ [weak self] in \(raw: statements.trimmedDescription) }"
        }
    }
}

public struct WithWeakSelfTaskMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in _: some MacroExpansionContext) throws -> ExprSyntax {
        let block = node.trailingClosure!

        var statements = CodeBlockItemListSyntax(stringLiteral: "guard let self else { return }")
        statements.append(contentsOf: block.statements)

        if let sig = block.signature?.tokens(viewMode: .fixedUp).map(\.trimmedDescription).joined(separator: " ") {
            return "Task { [weak self] \(raw: sig) \(raw: statements.trimmedDescription) }"
        } else {
            return "Task { [weak self] in \(raw: statements.trimmedDescription) }"
        }
    }
}

@main
struct MinionsPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NotificationMacro.self,
        WithWeakSelfMacro.self,
        WithWeakSelfTaskMacro.self
    ]
}
