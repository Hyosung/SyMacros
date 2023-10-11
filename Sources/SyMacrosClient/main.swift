import SyMacros

let a = 17
let b = 25

let (result, code) = #stringify(a + b)

print("The value \(result) was produced by the code \"\(code)\"")

struct Constaints {
    #Constant("app_icon")
    #Constant("empty_image")
    #Constant("error_tip")
}

#if canImport(ObjectMapper)
import ObjectMapper

@Mappable
class BaseResponse {
    var code = 0
    var msg = ""
}

@Mappable(isSubclass: true)
struct TestC {
    
}

@Mappable(isSubclass: true)
class TestResponse: BaseResponse {
    var data = ""
}

@Mappable
struct TestModel {
    var itemTitle = ""
    var itemType = ""
    var helpItems = [String]()
}

print(TestModel(JSON: ["itemTitle": "1", "itemType": "2", "helpItems": []]))
#endif

let obj = (key: "123", obj: "")
#mainBundle("123", Int.self)
#mainBundle(obj.key)
#mainBundle("CFBundleVersion")

//@InterfaceGen
//class Merchant {
//    
//    private var name: String = ""
//    public var age: Int = 20
//
//    func product(num: Int, _ age: Int = 9) -> Int {
//        return 0
//    }
//    
//    private func test(_ num: inout Int, pp dd: [Int] = [0]) throws -> Int {
//        return 0
//    }
//}

