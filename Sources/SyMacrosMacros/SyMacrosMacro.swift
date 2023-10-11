import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.argumentList.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

public struct ConstantMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let name = node.argumentList.first?
            .expression
            .as(StringLiteralExprSyntax.self)?
            .segments
            .first?
            .as(StringSegmentSyntax.self)?
            .content.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fatalError("compiler bug: invalid arguments")
        }
        let camelName = name.components(separatedBy: "_")
            .enumerated()
            .map { $0.offset > 0 ? $0.element.capitalized : $0.element.lowercased() }
            .joined()
        
        return ["static var \(raw: camelName) = { \(literal: name) }"]
    }
}

extension MacroExpansionContext {
    func diagnose(node: SyntaxProtocol, message: SyMacrosDiagnostic) {
        diagnose(message.toDiagnostic(node: node))
    }
}

public struct InterfaceGenMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            // 只能绑定到类上
            // context.addDiagnostics(from: SyMacrosError.custom("只支持在class上使用"), node: node)
            // context.diagnose(SyMacrosDiagnostic.error("只支持在class上使用").toDiagnostic(node: node))
            context.diagnose(node: node, message: .error("只支持在class上使用"))
            return []
        }
        // 获取类名
        let classname = classDecl.name.text
        
        // 获取成员变量
        let variables = classDecl.memberBlock.members
            .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
            .compactMap({ decl -> (String, String)? in
                let isPrivate = decl.modifiers.contains {
                    if case .keyword(let keyword) = $0.name.tokenKind, keyword == .private {
                        return true
                    }
                    return false
                }
                if isPrivate {
                    return nil
                }
                
                guard let name = decl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let type = decl.bindings.first?.typeAnnotation?.type.description else {
                    return nil
                }
                return (name, type)
            })
            .map({ "var \($0.0): \($0.1) { get }" })
            .joined(separator: "\n")
        
        let functions = classDecl.memberBlock.members
            .compactMap({ $0.decl.as(FunctionDeclSyntax.self) })
            .compactMap({ decl -> String? in
                let isPrivate = decl.modifiers.contains {
                    if case .keyword(let keyword) = $0.name.tokenKind, keyword == .private {
                        return true
                    }
                    return false
                }
                
                if isPrivate {
                    // 私有方法不公开
                    return nil
                }
                
                var newDecl = decl
                // 去掉方法体
                newDecl.body = nil
                var signature = newDecl.signature
                var parameterClause = signature.parameterClause
                var parameters: FunctionParameterListSyntax?
                for var parameter in parameterClause.parameters {
                    // 去掉参数默认值
                    parameter.defaultValue = nil
                    if parameters == nil {
                        parameters = FunctionParameterListSyntax(arrayLiteral: parameter)
                    } else {
                        parameters?.append(parameter)
                    }
                }
                if let parameters {
                    parameterClause.parameters = parameters
                }
                signature.parameterClause = parameterClause
                newDecl.signature = signature
                
                var descr = newDecl.trimmedDescription
                if let range = descr.range(of: parameterClause.trimmedDescription) {
                    descr.replaceSubrange(range, with: "(\(parameterClause.parameters.trimmedDescription))")
                }
                return descr
            })
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .joined(separator: "\n")
        return ["""
        public protocol \(raw: classname)Interface: AnyObject {
        \(raw: variables)
        
        \(raw: functions)
        }
        """]
    }
}

public struct MappableMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if let list = handleClass(of: node, providingMembersOf: declaration, in: context) {
            return list
        } else if let list = handleStruct(of: node, providingMembersOf: declaration, in: context) {
            return list
        }
        context.addDiagnostics(from: SyMacrosError.unsupportType, node: node)
        return []
    }
    
    private static func allMappedPropertys(_ members: MemberBlockItemListSyntax) -> String {
        members
            .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
            .compactMap({ decl -> String? in
                guard let name = decl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    return nil
                }
                return name
            })
            .map({ "    \($0) <- map[\"\($0)\"]" })
            .joined(separator: "\n")
    }
    
    private static func handleClass(of node: AttributeSyntax,
                                    providingMembersOf declaration: some DeclGroupSyntax,
                                    in context: some MacroExpansionContext) -> [DeclSyntax]? {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return nil
        }
        
        var isSubclass = false
        if let isSubclassItem = node.arguments?.as(LabeledExprListSyntax.self)?.first(where: { $0.label?.text == "isSubclass" }) {
            isSubclass = isSubclassItem.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
        }
        
        if isSubclass, classDecl.inheritanceClause == nil {
            context.diagnose(node: node, message: .error("The inherited class was not found"))
            return []
        }
        
        let code = allMappedPropertys(classDecl.memberBlock.members)
        let isInitExists = classDecl.memberBlock.members.contains {
            guard let initializerDecl = $0.decl.as(InitializerDeclSyntax.self) else {
                return false
            }
            return initializerDecl.trimmedDescription.range(of: #"required\s+init\s*\?\s*\(\s*map\s*:\s*(ObjectMapper\.)?Map\s*\)"#, options: .regularExpression) != nil
        }
        
        var initCode = ""
        if !isInitExists {
            if isSubclass {
                initCode = """
                required init?(map: ObjectMapper.Map) {
                    super.init(map: map)
                }\n
                """
            } else {
                initCode = "required init?(map: ObjectMapper.Map) {}\n"
            }
        }
        
        let overrideText = isSubclass ? "override " : ""
        let superCallText = isSubclass ? "\n    super.mapping(map: map)" : ""
        return [
        """
        
        \(raw: initCode)
        \(raw: overrideText)func mapping(map: ObjectMapper.Map) {\(raw: superCallText)
        \(raw: code)
        }
        """
        ]
    }
    
    private static func handleStruct(of node: AttributeSyntax,
                                     providingMembersOf declaration: some DeclGroupSyntax,
                                     in context: some MacroExpansionContext) -> [DeclSyntax]? {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return nil
        }
        
        if node.arguments?.as(LabeledExprListSyntax.self)?.contains(where: { $0.label?.text == "isSubclass" }) == true {
            context.diagnose(node: node, message: .warning("struct does not support isSubclass"))
        }
        
        let code = allMappedPropertys(structDecl.memberBlock.members)
        
        let isInitExists = structDecl.memberBlock.members.contains {
            $0.decl.as(InitializerDeclSyntax.self)?.trimmedDescription.range(of: #"init\s*\?\s*\(\s*map\s*:\s*(ObjectMapper\.)?Map\s*\)"#, options: .regularExpression) != nil
        }
        
        var initCode = ""
        if !isInitExists {
            initCode = "init?(map: ObjectMapper.Map) {}\n"
        }
        
        return [
        """
        \(raw: initCode)
        mutating func mapping(map: ObjectMapper.Map) { 
        \(raw: code)
        }
        """
        ]
    }
}

extension MappableMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        var isSubclass = false
        if let isSubclassItem = node.arguments?.as(LabeledExprListSyntax.self)?.first(where: { $0.label?.text == "isSubclass" }) {
            isSubclass = isSubclassItem.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
        }
        if isSubclass {
            return []
        }
        let mappableExtension = try ExtensionDeclSyntax("extension \(type.trimmed): Mappable {}")
        return [mappableExtension]
    }
}

public struct MainBundleMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        guard let keyArgument = node.argumentList.first?.expression else {
            context.diagnose(node: node, message: .error("Missing required parameter 'infoPlistKey'"))
            return ""
        }
        
        var type = "String"
        if node.argumentList.count == 2, 
            let typeArgument = node.argumentList.last?.expression.as(MemberAccessExprSyntax.self), let t = typeArgument.base?.trimmedDescription {
            type = t
        }
        return "Bundle.main.object(forInfoDictionaryKey: \(raw: keyArgument.trimmedDescription)) as? \(raw: type)"
    }
}

enum SyMacrosError: CustomStringConvertible, Error {
    case unsupportType
    case custom(String)
    
    var description: String {
        switch self {
        case .custom(let string):
            return string
        case .unsupportType:
            return "不支持的类型"
        }
    }
}

enum SyMacrosDiagnostic: DiagnosticMessage {
    case error(String)
    case warning(String)
    
    // 诊断信息类型，warning/error
    var severity: DiagnosticSeverity {
        switch self {
        case .error: return .error
        case .warning: return .warning
        }
    }
    
    var message: String {
        switch self {
        case .error(let string), .warning(let string):
            return string
        }
    }
    
    private var id: String {
        switch self {
        case .error(let string):
            return "error\(string)"
        case .warning(let string):
            return "warning\(string)"
        }
    }
    
    // 诊断唯一标识
    var diagnosticID: MessageID {
        MessageID(domain: "SyMacrosDiagnostic", id: id)
    }
    
    func toDiagnostic(node: SyntaxProtocol) -> Diagnostic {
        Diagnostic(node: node._syntaxNode, message: self)
    }
}

@main
struct SyMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ConstantMacro.self,
        StringifyMacro.self,
        InterfaceGenMacro.self,
        MappableMacro.self,
        MainBundleMacro.self,
    ]
}
