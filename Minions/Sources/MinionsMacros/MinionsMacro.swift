import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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
        WithWeakSelfMacro.self,
        WithWeakSelfTaskMacro.self
    ]
}
