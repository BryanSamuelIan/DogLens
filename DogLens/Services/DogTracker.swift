import Foundation
import CoreGraphics

// MARK: - Dog Multi-Object Tracker (IoU Tracker + Re-Entry Re-ID + Temporal Track Merging)

final class DogTracker {
    private var nextTrackId: Int = 1
    private(set) var activeTracks: [TrackedDog] = []
    private(set) var allEncounteredTracks: [TrackedDog] = []
    
    var iouThreshold: CGFloat = 0.25
    var maxLostFrames: Int = 45       // ~3.0s at 15fps (tolerates brief occlusions & turns)
    var maxReentryFrames: Int = 90    // ~6.0s at 15fps (re-identifies dog exiting & re-entering frame)
    var baseDetectionThreshold: Float = 0.30
    
    init(iouThreshold: CGFloat = 0.25, maxLostFrames: Int = 45, maxReentryFrames: Int = 90, baseDetectionThreshold: Float = 0.30) {
        self.iouThreshold = iouThreshold
        self.maxLostFrames = maxLostFrames
        self.maxReentryFrames = maxReentryFrames
        self.baseDetectionThreshold = baseDetectionThreshold
    }
    
    /// Process a new frame's raw detections and return smoothed, ID-tagged detections
    func processFrame(detections: [DetectionResult], frameIndex: Int) -> [DetectionResult] {
        var unmatchedDetections = detections
        
        // 1. Build list of potential matches with ACTIVE tracks (trackIndex, detIndex, iou)
        var candidates: [(trackIdx: Int, detIdx: Int, iou: CGFloat)] = []
        for (tIdx, track) in activeTracks.enumerated() {
            for (dIdx, det) in unmatchedDetections.enumerated() {
                let iou = calculateIoU(rect1: track.currentBox, rect2: det.boundingBox)
                if iou >= iouThreshold {
                    candidates.append((trackIdx: tIdx, detIdx: dIdx, iou: iou))
                }
            }
        }
        
        // Sort descending by IoU so strongest overlaps pair first
        candidates.sort { $0.iou > $1.iou }
        
        var matchedTrackIndices = Set<Int>()
        var matchedDetectionIndices = Set<Int>()
        
        for candidate in candidates {
            if !matchedTrackIndices.contains(candidate.trackIdx) && !matchedDetectionIndices.contains(candidate.detIdx) {
                matchedTrackIndices.insert(candidate.trackIdx)
                matchedDetectionIndices.insert(candidate.detIdx)
                
                let det = unmatchedDetections[candidate.detIdx]
                activeTracks[candidate.trackIdx].update(
                    box: det.boundingBox,
                    frameIndex: frameIndex,
                    breed: det.label,
                    confidence: det.confidence
                )
            }
        }
        
        // Increase lost counter for active tracks that weren't matched in this frame
        for (tIdx, track) in activeTracks.enumerated() {
            if !matchedTrackIndices.contains(tIdx) {
                track.lostFrameCount += 1
            }
        }
        
        // 2. Re-entry & Re-ID matching for unmatched detections:
        // Check if detection belongs to a previously seen track of the same breed that left the frame
        var reidentifiedTrackIds = Set<Int>()
        
        for (dIdx, det) in unmatchedDetections.enumerated() {
            guard !matchedDetectionIndices.contains(dIdx) else { continue }
            
            // Find inactive tracks of the same breed that were seen within maxReentryFrames
            let inactiveCandidates = allEncounteredTracks.filter { track in
                guard track.lastSeenFrame < frameIndex else { return false }
                guard !reidentifiedTrackIds.contains(track.id) else { return false }
                guard (frameIndex - track.lastSeenFrame) <= maxReentryFrames else { return false }
                
                if let consensus = track.getConsensusBreed(baseThreshold: baseDetectionThreshold) {
                    return consensus.breed.caseInsensitiveCompare(det.label) == .orderedSame
                }
                return false
            }
            
            // Pick the candidate that was most recently seen
            if let bestMatch = inactiveCandidates.max(by: { $0.lastSeenFrame < $1.lastSeenFrame }) {
                bestMatch.update(
                    box: det.boundingBox,
                    frameIndex: frameIndex,
                    breed: det.label,
                    confidence: det.confidence
                )
                bestMatch.lostFrameCount = 0
                
                if !activeTracks.contains(where: { $0.id == bestMatch.id }) {
                    activeTracks.append(bestMatch)
                }
                
                reidentifiedTrackIds.insert(bestMatch.id)
                matchedDetectionIndices.insert(dIdx)
            }
        }
        
        // 3. Create new tracks ONLY for detections that didn't match any active or inactive track
        for (dIdx, det) in unmatchedDetections.enumerated() {
            if !matchedDetectionIndices.contains(dIdx) {
                let newTrack = TrackedDog(
                    id: nextTrackId,
                    box: det.boundingBox,
                    frameIndex: frameIndex,
                    initialBreed: det.label,
                    confidence: det.confidence
                )
                nextTrackId += 1
                activeTracks.append(newTrack)
                allEncounteredTracks.append(newTrack)
            }
        }
        
        // 4. Prune tracks that have been lost for too long from active list
        activeTracks.removeAll { $0.lostFrameCount > maxLostFrames }
        
        // 5. Return smoothed DetectionResult for currently visible dogs
        return activeTracks.compactMap { track in
            guard track.lastSeenFrame == frameIndex else { return nil }
            
            if let consensus = track.getConsensusBreed(baseThreshold: baseDetectionThreshold) {
                let label = "Dog #\(track.id): \(consensus.breed)"
                return DetectionResult(boundingBox: track.currentBox, label: label, confidence: consensus.confidence)
            } else {
                let label = "Dog #\(track.id)"
                return DetectionResult(boundingBox: track.currentBox, label: label, confidence: 0.0)
            }
        }
    }
    
    // MARK: - Temporal Track Merging
    
    /// Consolidates tracks that belong to the same breed and never co-existed in the same frame
    /// (e.g. a dog walking out of frame and returning later).
    func consolidateTracks(minFrames: Int = 2) -> [TrackedDog] {
        let validTracks = allEncounteredTracks.filter { $0.totalFramesSeen >= minFrames }
        guard !validTracks.isEmpty else { return [] }
        
        var consolidated: [TrackedDog] = []
        
        for track in validTracks {
            guard let trackBreed = track.getConsensusBreed(baseThreshold: baseDetectionThreshold)?.breed else {
                consolidated.append(track)
                continue
            }
            
            // Look for an existing consolidated track with the same breed that NEVER overlapped in time
            if let matchIndex = consolidated.firstIndex(where: { existing in
                guard let existingBreed = existing.getConsensusBreed(baseThreshold: self.baseDetectionThreshold)?.breed else {
                    return false
                }
                return existingBreed.caseInsensitiveCompare(trackBreed) == .orderedSame && !existing.overlapsInTime(with: track)
            }) {
                // Merge this track into the existing track
                consolidated[matchIndex].merge(with: track)
            } else {
                consolidated.append(track)
            }
        }
        
        // Renumber consolidated dogs sequentially (Dog #1, Dog #2, etc.)
        for (index, dog) in consolidated.enumerated() {
            dog.id = index + 1
        }
        
        return consolidated
    }
    
    /// Returns consolidated dog summaries for the result screen
    func getConsolidatedSummaries(minFrames: Int = 2, highConfidenceThreshold: Float = 0.70) -> [TrackedDogSummary] {
        let consolidated = consolidateTracks(minFrames: minFrames)
        return consolidated.map { $0.toSummary(highConfidenceThreshold: highConfidenceThreshold) }
    }
    
    // MARK: - IoU Calculation
    private func calculateIoU(rect1: CGRect, rect2: CGRect) -> CGFloat {
        let intersection = rect1.intersection(rect2)
        guard !intersection.isNull && !intersection.isEmpty else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let area1 = rect1.width * rect1.height
        let area2 = rect2.width * rect2.height
        let unionArea = area1 + area2 - intersectionArea
        
        return unionArea > 0 ? (intersectionArea / unionArea) : 0
    }
    
    func reset() {
        activeTracks.removeAll()
        allEncounteredTracks.removeAll()
        nextTrackId = 1
    }
}
