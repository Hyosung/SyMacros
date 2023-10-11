import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(SyMacrosMacros)
    import SyMacrosMacros

    let testMacros: [String: Macro.Type] = [
        "stringify": StringifyMacro.self,
    ]
#endif

final class SyMacrosTests: XCTestCase {
    func testMacro() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                """
                #stringify(a + b)
                """,
                expandedSource: """
                (a + b, "a + b")
                """,
                macros: testMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMacroWithStringLiteral() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                #"""
                #stringify("Hello, \(name)")
                """#,
                expandedSource: #"""
                ("Hello, \(name)", #""Hello, \(name)""#)
                """#,
                macros: testMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testClassMappable() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                """
                @Mappable
                class Merchant {

                    var name = ""
                    var age = 0

                    public required  init?(map: ObjectMapper.Map ) {
                        print("")
                    }
                }
                """,
                expandedSource: """
                class Merchant {

                    var name = ""
                    var age = 0

                    public required  init?(map: ObjectMapper.Map ) {
                        print("")
                    }

                    func mapping(map: ObjectMapper.Map) {
                        name <- map["name"]
                        age <- map["age"]
                    }
                }

                extension Merchant: Mappable {
                }
                """,
                macros: ["Mappable": MappableMacro.self])
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    func testSubclassMappable() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                """
                @Mappable
                class BaseResponse: Codable {
                    var code = 0
                    var msg = ""
                }

                @Mappable(isSubclass: true)
                class TestResponse: BaseResponse {
                    var data = ""
                }
                """,
                expandedSource: """
                class BaseResponse {
                    var code = 0
                    var msg = ""
                
                    required init?(map: ObjectMapper.Map) {
                    }
                
                    func mapping(map: ObjectMapper.Map) {
                        code <- map["code"]
                        msg <- map["msg"]
                    }
                }
                class TestResponse: BaseResponse {
                    var data = ""
                
                    required init?(map: ObjectMapper.Map) {
                        super.init(map: map)
                    }
                
                    override func mapping(map: ObjectMapper.Map) {
                        super.mapping(map: map)
                        data <- map["data"]
                    }
                }
                
                extension BaseResponse: Mappable {
                }
                """,
                macros: ["Mappable": MappableMacro.self])
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStructMappable() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                """
                @Mappable
                struct Merchant {

                    var name = ""
                    var age = 0

                    public  init?(map: ObjectMapper.Map ) {
                        print("")
                    }
                }
                """,
                expandedSource: """
                struct Merchant {

                    var name = ""
                    var age = 0

                    public  init?(map: ObjectMapper.Map ) {
                        print("")
                    }

                    mutating func mapping(map: ObjectMapper.Map) {
                        name <- map["name"]
                        age <- map["age"]
                    }
                }

                extension Merchant: Mappable {
                }
                """,
                macros: ["Mappable": MappableMacro.self])
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    func testMainBundle() throws {
        #if canImport(SyMacrosMacros)
            assertMacroExpansion(
                """
                let key = "123"
                #mainBundle("key", Int.self)
                #mainBundle(key)
                """,
                expandedSource: """
                let key = "123"
                Bundle.main.object(forInfoDictionaryKey: "key") as? Int
                Bundle.main.object(forInfoDictionaryKey: key) as? String
                """,
                macros: ["mainBundle": MainBundleMacro.self])
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
