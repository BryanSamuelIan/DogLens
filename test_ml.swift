import CoreML
import Foundation

// Just checking if syntax is correct
let multiArray = try! MLMultiArray(shape: [1, 56, 3549], dataType: .float32)

let count = multiArray.count
let ptr32 = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: count)

let floatVal = ptr32[0]

let ptr16 = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: count)
let floatVal2 = Float(ptr16[0])

print("Compiled fine: \(floatVal), \(floatVal2)")
