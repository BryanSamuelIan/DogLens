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
    private let container = CKContainer.default()
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
        
        record["mediaId"] = breedImage.id.uuidString as CKRecordValue
        record["breedName"] = breedName as CKRecordValue
        record["confidence"] = breedImage.confidence as CKRecordValue
        record["isVideo"] = (breedImage.isVideo ? 1 : 0) as CKRecordValue
        record["detectionDate"] = breedImage.detectionDate as CKRecordValue
        
        // Save Original Image Asset
        if let originalImageURL = createTempFile(data: breedImage.imageData, ext: "jpg") {
            record["imageAsset"] = CKAsset(fileURL: originalImageURL)
        }
        
        // Save Annotated Image Asset
        if let annotatedData = breedImage.annotatedImageData,
           let annotatedImageURL = createTempFile(data: annotatedData, ext: "jpg") {
            record["annotatedImageAsset"] = CKAsset(fileURL: annotatedImageURL)
        }
        
        // Save Raw Video Asset
        if let videoData = breedImage.videoData,
           let videoURL = createTempFile(data: videoData, ext: "mp4") {
            record["videoAsset"] = CKAsset(fileURL: videoURL)
        }
        
        // Save Annotated Video Asset
        if let annotatedVideoData = breedImage.annotatedVideoData,
           let annotatedVideoURL = createTempFile(data: annotatedVideoData, ext: "mp4") {
            record["annotatedVideoAsset"] = CKAsset(fileURL: annotatedVideoURL)
        }
        
        do {
            let savedRecord = try await database.save(record)
            self.syncState = .synced(Date())
            self.lastSyncDate = Date()
            self.backedUpItemCount += 1
            return savedRecord.recordID
        } catch {
            self.syncState = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Fetch Cloud Media
    
    func fetchCloudMedia() async throws -> [CKRecord] {
        syncState = .syncing
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "detectionDate", ascending: false)]
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            var records: [CKRecord] = []
            
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            
            self.syncState = .synced(Date())
            self.lastSyncDate = Date()
            self.backedUpItemCount = records.count
            return records
        } catch {
            self.syncState = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Delete Cloud Media
    
    func deleteCloudMedia(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        _ = try await database.deleteRecord(withID: recordID)
        self.backedUpItemCount = max(0, self.backedUpItemCount - 1)
    }
    
    // MARK: - Item Count Query
    
    func refreshCloudItemCount() async {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            self.backedUpItemCount = matchResults.count
            self.syncState = .synced(Date())
        } catch {
            // Silently fallback if iCloud is offline or in simulator
            self.syncState = .idle
        }
    }
    
    // MARK: - Sync with Local SwiftData
    
    func syncWithLocalDatabase(modelContext: ModelContext) async {
        guard let records = try? await fetchCloudMedia() else { return }
        
        let fetchDescriptor = FetchDescriptor<DogBreed>()
        guard let allBreeds = try? modelContext.fetch(fetchDescriptor) else { return }
        
        for record in records {
            guard let mediaIdString = record["mediaId"] as? String,
                  let mediaUUID = UUID(uuidString: mediaIdString),
                  let breedName = record["breedName"] as? String,
                  let confidence = record["confidence"] as? Double,
                  let isVideoInt = record["isVideo"] as? Int64,
                  let detectionDate = record["detectionDate"] as? Date,
                  let imageAsset = record["imageAsset"] as? CKAsset,
                  let imageFileURL = imageAsset.fileURL,
                  let imageData = try? Data(contentsOf: imageFileURL) else {
                continue
            }
            
            // Check if local breed exists
            guard let breed = allBreeds.first(where: { $0.name == breedName }) else { continue }
            
            // Check if already in local database
            let existingImages = breed.images
            if existingImages.contains(where: { $0.id == mediaUUID }) {
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
            
            let newEntry = BreedImage(
                id: mediaUUID,
                imageData: imageData,
                annotatedImageData: annotatedImageData,
                videoData: videoData,
                annotatedVideoData: annotatedVideoData,
                isVideo: isVideoInt == 1,
                detectionDate: detectionDate,
                confidence: confidence,
                breed: breed
            )
            breed.images.append(newEntry)
        }
        
        try? modelContext.save()
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
