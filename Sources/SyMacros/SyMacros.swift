// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.

// 独立式-表达式宏
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "SyMacrosMacros", type: "StringifyMacro")

@freestanding(expression)
public macro mainBundle<T>(_ infoPlistKey: String, _ type: T.Type = String.self) -> T? = #externalMacro(module: "SyMacrosMacros", type: "MainBundleMacro")

// 独立式-声明式宏
@freestanding(declaration, names: arbitrary)
public macro Constant(_ value: String) = #externalMacro(module: "SyMacrosMacros", type: "ConstantMacro")

//// 绑定式-对等宏
//@attached(peer)
//public macro InterfaceGen() = #externalMacro(module: "SyMacrosMacros", type: "InterfaceGenMacro")

#if canImport(ObjectMapper)
import ObjectMapper
// 绑定式-成员宏
@attached(member, names: named(init(map:)), named(mapping(map:)))
@attached(extension, conformances: Mappable, names: named(mapping(map:)), named(init(map:)))
public macro Mappable(isSubclass: Bool = false) = #externalMacro(module: "SyMacrosMacros", type: "MappableMacro")
#endif
