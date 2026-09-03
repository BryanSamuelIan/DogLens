import Foundation
import CloudKit
import SwiftData
import Combine

// MARK: - CloudKit Sync State

enum CloudSyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "iCloud Ready"
        case .syncing:
            return "Syncing with iCloud…"
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .error(let msg):
            return "Sync Error: \(msg)"
        }
    }
}

// MARK: - CloudKit Service

@MainActor
final class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    // CloudKit configuration
    private let container: CKContainer = {
        let identifier = "iCloud.DogLens"
        return CKContainer(identifier: identifier)
    }()
    private var database: CKDatabase {
        container.privateCloudDatabase
    }
    
    public static let recordType = "BreedMedia"
    
    // Published State
    @Published var syncState: CloudSyncState = .idle
    @Published var backedUpItemCount: Int = 0
    @Published var lastSyncDate: Date? = nil
    
    private init() {
        Task {
            await refreshCloudItemCount()
        }
    }
    
    // MARK: - Upload Breed Media
    
    /// Uploads a BreedImage (Photo or Video) and its assets to CloudKit private database
    @discardableResult
    func uploadBreedMedia(breedImage: BreedImage, breedName: String) async throws -> CKRecord.ID {
        syncState = .syncing
        
        let recordID = CKRecord.ID(recordName: breedImage.id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        
        // Write both mediaId and localID for cross-compatibility with Mac
        record["mediaId"] = breedImage.id.uuidString as CKRecordValue
        record["localID"] = breedImage.id.uuidString as CKRecordValue
        record["breedName"] = breedName as CKRecordValue
        record["confidence"] = breedImage.confidence as CKRecordValue
        record["isVideo"] = (breedImage.isVideo ? 1 : 0) as CKRecordValue
        record["detectionDate"] = breedImage.detectionDate as CKRecordValue
        
        var tempFiles: [URL] = []
        
        // Save Original Image Asset
        if let originalImageURL = createTempFile(data: breedImage.imageData, ext: "jpg") {
            record["imageAsset"] = CKAsset(fileURL: originalImageURL)
            tempFiles.append(originalImageURL)
        }
        
        // Save Annotated Image Asset
        if let annotatedData = breedImage.annotatedImageData,
           let annotatedImageURL = createTempFile(data: annotatedData, ext: "jpg") {
            record["annotatedImageAsset"] = CKAsset(fileURL: annotatedImageURL)
            tempFiles.append(annotatedImageURL)
        }
        
        // Save Raw Video Asset
        if let videoData = breedImage.videoData,
           let videoURL = createTempFile(data: videoData, ext: "mp4") {
            record["videoAsset"] = CKAsset(fileURL: videoURL)
            tempFiles.append(videoURL)
        }
        
        // Save Annotated Video Asset
        if let annotatedVideoData = breedImage.annotatedVideoData,
           let annotatedVideoURL = createTempFile(data: annotatedVideoData, ext: "mp4") {
            record["annotatedVideoAsset"] = CKAsset(fileURL: annotatedVideoURL)
            tempFiles.append(annotatedVideoURL)
        }
        
        do {
            let savedRecord = try await database.save(record)
            self.syncState = .synced(Date())
            self.lastSyncDate = Date()
            self.backedUpItemCount += 1
            
            // Clean up temp files
            for url in tempFiles {
                try? FileManager.default.removeItem(at: url)
            }
            
            print("[iOS CloudKit] Successfully uploaded BreedMedia \(breedImage.id)")
            return savedRecord.recordID
        } catch {
            self.syncState = .error(error.localizedDescription)
            print("[iOS CloudKit] Upload failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch Cloud Media (With Cursor Pagination)
    
    func fetchCloudMedia() async throws -> [CKRecord] {
        syncState = .syncing
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        
        var records: [CKRecord] = []
        
        do {
            var (matchResults, cursor) = try await database.records(matching: query)
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            
            // Paginate through all remaining records
            while let currentCursor = cursor {
                let (nextResults, nextCursor) = try await database.records(continuingMatchFrom: currentCursor)
                for (_, result) in nextResults {
                    if case .success(let record) = result {
                        records.append(record)
                    }
                }
                cursor = nextCursor
            }
            
            // Sort in memory to avoid requiring a custom SORTABLE index in CloudKit console
            records.sort {
                let d1 = ($0["detectionDate"] as? Date) ?? $0.creationDate ?? .distantPast
                let d2 = ($1["detectionDate"] as? Date) ?? $1.creationDate ?? .distantPast
                return d1 > d2
            }
            
            self.syncState = .synced(Date())
            self.lastSyncDate = Date()
            self.backedUpItemCount = records.count
            print("[iOS CloudKit] Fetched \(records.count) total records from CloudKit.")
            return records
        } catch {
            print("[iOS CloudKit] Fetch failed on iOS: \(error)")
            self.syncState = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Delete Cloud Media
    
    /// Deletes a batch of records from CloudKit private database
    func deleteCloudMedia(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
        
        do {
            let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs)
            var deletedCount = 0
            for (_, result) in deleteResults {
                if case .success = result {
                    deletedCount += 1
                }
            }
            self.backedUpItemCount = max(0, self.backedUpItemCount - deletedCount)
            print("[iOS CloudKit] Successfully deleted \(deletedCount)/\(recordNames.count) records from CloudKit.")
        } catch {
            print("[iOS CloudKit] Batch deletion error: \(error)")
            // Fallback to individual deletion if batch modification encounters partial/policy failure
            var deletedCount = 0
            for id in recordIDs {
                if (try? await database.deleteRecord(withID: id)) != nil {
                    deletedCount += 1
                }
            }
            self.backedUpItemCount = max(0, self.backedUpItemCount - deletedCount)
        }
    }
    
    /// Deletes a single record from CloudKit private database
    func deleteCloudMedia(recordName: String) async throws {
        try await deleteCloudMedia(recordNames: [recordName])
    }
    
    // MARK: - Item Count Query
    
    func refreshCloudItemCount() async {
        do {
            let records = try await fetchCloudMedia()
            self.backedUpItemCount = records.count
            self.syncState = .synced(Date())
        } catch {
            self.syncState = .idle
        }
    }
    
    // MARK: - Sync with Local SwiftData (Resilient & Non-Dropping)
    
    func syncWithLocalDatabase(modelContext: ModelContext) async {
        guard let records = try? await fetchCloudMedia() else { return }
        
        // Fetch existing images to prevent duplication
        let existingDescriptor = FetchDescriptor<BreedImage>()
        let existingImages = (try? modelContext.fetch(existingDescriptor)) ?? []
        let existingIDs = Set(existingImages.map { $0.id.uuidString.lowercased() })
        
        let breedDescriptor = FetchDescriptor<DogBreed>()
        let allBreeds = (try? modelContext.fetch(breedDescriptor)) ?? []
        var breedDict: [String: DogBreed] = [:]
        for b in allBreeds {
            breedDict[b.name.lowercased()] = b
        }
        
        var downloadedCount = 0
        
        for record in records {
            // Support mediaId, localID, or recordName
            let idString = (record["mediaId"] as? String)
                ?? (record["localID"] as? String)
                ?? record.recordID.recordName
            
            guard let mediaUUID = UUID(uuidString: idString) else {
                print("[iOS CloudKit] Skipping record \(record.recordID.recordName): invalid UUID")
                continue
            }
            
            if existingIDs.contains(mediaUUID.uuidString.lowercased()) {
                continue
            }
            
            let breedName = (record["breedName"] as? String) ?? "Unknown Breed"
            
            let confidence = (record["confidence"] as? Double)
                ?? ((record["confidence"] as? NSNumber)?.doubleValue)
                ?? 0.0
            
            let isVideo: Bool
            if let vInt = record["isVideo"] as? Int64 {
                isVideo = (vInt == 1)
            } else if let vInt = record["isVideo"] as? Int {
                isVideo = (vInt == 1)
            } else if let vNum = record["isVideo"] as? NSNumber {
                isVideo = (vNum.intValue == 1)
            } else {
                isVideo = false
            }
            
            let detectionDate = (record["detectionDate"] as? Date)
                ?? record.creationDate
                ?? Date()
            
            var imageData = Data()
            if let imageAsset = record["imageAsset"] as? CKAsset,
               let imageFileURL = imageAsset.fileURL,
               let data = try? Data(contentsOf: imageFileURL) {
                imageData = data
            }
            
            guard !imageData.isEmpty else {
                print("[iOS CloudKit] Record \(mediaUUID) has empty image data, skipping.")
                continue
            }
            
            // Load optional assets
            var annotatedImageData: Data? = nil
            if let annotAsset = record["annotatedImageAsset"] as? CKAsset,
               let url = annotAsset.fileURL {
                annotatedImageData = try? Data(contentsOf: url)
            }
            
            var videoData: Data? = nil
            if let vidAsset = record["videoAsset"] as? CKAsset,
               let url = vidAsset.fileURL {
                videoData = try? Data(contentsOf: url)
            }
            
            var annotatedVideoData: Data? = nil
            if let annotVidAsset = record["annotatedVideoAsset"] as? CKAsset,
               let url = annotVidAsset.fileURL {
                annotatedVideoData = try? Data(contentsOf: url)
            }
            
            // Find or create local breed
            let breed: DogBreed
            if let existing = breedDict[breedName.lowercased()] {
                breed = existing
            } else {
                let newBreed = DogBreed(name: breedName)
                modelContext.insert(newBreed)
                breedDict[breedName.lowercased()] = newBreed
                breed = newBreed
            }
            
            let newEntry = BreedImage(
                id: mediaUUID,
                imageData: imageData,
                annotatedImageData: annotatedImageData,
                videoData: videoData,
                annotatedVideoData: annotatedVideoData,
                isVideo: isVideo,
                detectionDate: detectionDate,
                confidence: confidence,
                breed: breed
            )
            modelContext.insert(newEntry)
            breed.images.append(newEntry)
            downloadedCount += 1
        }
        
        do {
            try modelContext.save()
            print("[iOS CloudKit] Successfully synced local database with \(downloadedCount) new items.")
        } catch {
            print("[iOS CloudKit] Failed to save SwiftData after sync: \(error)")
        }
    }
    
    // MARK: - Helper: Create Temp File for CKAsset
    
    private func createTempFile(data: Data, ext: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}
