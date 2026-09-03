import Foundation
import CoreGraphics

// MARK: - Tracked Dog Model

final class TrackedDog: Identifiable {
    var id: Int
    var currentBox: CGRect
    var lastSeenFrame: Int
    var lostFrameCount: Int = 0
    private(set) var totalFramesSeen: Int = 0
    private(set) var seenFrames: Set<Int> = []
    
    // Breed name -> List of confidence scores recorded across frames
    private var breedHistory: [String: [Float]] = [:]
    
    init(id: Int, box: CGRect, frameIndex: Int, initialBreed: String, confidence: Float) {
        self.id = id
        self.currentBox = box
        self.lastSeenFrame = frameIndex
        self.totalFramesSeen = 1
        self.seenFrames = [frameIndex]
        recordPrediction(breed: initialBreed, confidence: confidence)
    }
    
    func update(box: CGRect, frameIndex: Int, breed: String, confidence: Float) {
        self.currentBox = box
        self.lastSeenFrame = frameIndex
        self.lostFrameCount = 0
        self.totalFramesSeen += 1
        self.seenFrames.insert(frameIndex)
        recordPrediction(breed: breed, confidence: confidence)
    }
    
    private func recordPrediction(breed: String, confidence: Float) {
        if breedHistory[breed] == nil {
            breedHistory[breed] = []
        }
        breedHistory[breed]?.append(confidence)
    }
    
    /// Merges another track of the same breed into this track
    func merge(with other: TrackedDog) {
        self.seenFrames.formUnion(other.seenFrames)
        self.totalFramesSeen = seenFrames.count
        self.lastSeenFrame = max(self.lastSeenFrame, other.lastSeenFrame)
        
        for (breed, confidences) in other.breedHistory {
            if self.breedHistory[breed] == nil {
                self.breedHistory[breed] = []
            }
            self.breedHistory[breed]?.append(contentsOf: confidences)
        }
    }
    
    /// Checks if this track co-existed in more than `maxAllowedOverlapFrames` with another track.
    /// Filters out transient 1-3 frame noise/flicker double-bounding-boxes.
    func overlapsInTime(with other: TrackedDog, maxAllowedOverlapFrames: Int = 3) -> Bool {
        let intersectionCount = self.seenFrames.intersection(other.seenFrames).count
        return intersectionCount > maxAllowedOverlapFrames
    }
    
    /// Returns the consensus breed using temporal voting and peak confidence.
    func getConsensusBreed(baseThreshold: Float = 0.30) -> (breed: String, confidence: Float)? {
        guard !breedHistory.isEmpty else { return nil }
        
        var bestBreed: String? = nil
        var highestScore: Float = 0.0
        var bestConfidence: Float = 0.0
        
        for (breed, confidences) in breedHistory {
            let valid = confidences.filter { $0 >= baseThreshold }
            guard !valid.isEmpty else { continue }
            
            let maxConf = valid.max() ?? 0.0
            let avgConf = valid.reduce(0, +) / Float(valid.count)
            // Score based on occurrence frequency and model confidence
            let score = Float(valid.count) * (0.5 * maxConf + 0.5 * avgConf)
            
            if score > highestScore {
                highestScore = score
                bestBreed = breed
                bestConfidence = maxConf
            }
        }
        
        if let breed = bestBreed {
            return (breed, bestConfidence)
        }
        
        // Fallback: Pick highest occurrence overall
        if let fallback = breedHistory.max(by: { $0.value.count < $1.value.count }),
           let maxConf = fallback.value.max() {
            return (fallback.key, maxConf)
        }
        
        return nil
    }
    
    /// Summary representation for display in result views
    func toSummary(highConfidenceThreshold: Float = 0.70) -> TrackedDogSummary {
        let consensus = getConsensusBreed(baseThreshold: 0.30)
        let breed = consensus?.breed ?? "Unknown Dog"
        let conf = consensus?.confidence ?? 0.0
        return TrackedDogSummary(
            id: id,
            breedName: breed,
            confidence: Double(conf),
            isHighConfidence: conf >= highConfidenceThreshold,
            totalFrames: totalFramesSeen
        )
    }
}

// MARK: - Tracked Dog Summary

struct TrackedDogSummary: Identifiable {
    let id: Int
    let breedName: String
    let confidence: Double
    let isHighConfidence: Bool
    let totalFrames: Int
    
    var displayName: String {
        "Dog #\(id)"
    }
}
