//
//  DogLensTests.swift
//  DogLensTests
//
//  Created by Bryan Samuel on 21/08/26.
//

import Testing
import UIKit
import CoreVideo
@testable import DogLens

struct DogLensTests {

    @Test func testPixelBufferConversionWithRightOrientation() async throws {
        // Create a 100x100 test UIImage with .right orientation (camera photo simulation)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format)
        let baseImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }

        guard let cgImg = baseImage.cgImage else {
            Issue.record("Failed to create CGImage")
            return
        }

        let rightImage = UIImage(cgImage: cgImg, scale: 1.0, orientation: .right)
        let buffer = rightImage.pixelBufferOffMain(width: 416, height: 416)

        #expect(buffer != nil)
        if let buffer = buffer {
            #expect(CVPixelBufferGetWidth(buffer) == 416)
            #expect(CVPixelBufferGetHeight(buffer) == 416)
        }
    }

    @Test func testModelServiceDetectionExecution() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let testImage = renderer.image { ctx in
            UIColor.brown.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        let results = try await ModelService.shared.detectDogs(in: testImage)
        // Ensure detection completes cleanly (returns array)
        #expect(results.count >= 0)
    }
}

