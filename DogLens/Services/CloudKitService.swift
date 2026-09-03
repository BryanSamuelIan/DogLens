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
    
    // Persistent Pending Deletions Key
    private let pendingDeletionsKey = "com.doglens.pendingCloudDeletions"
    
    private init() {
        Task {
            await refreshCloudItemCount()
        }
    }
    
    // MARK: - Pending Deletions Queue Helpers
    
    private func getPendingDeletions() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        return Set(array)
    }
    
    private func addPendingDeletions(_ names: [String]) {
        var current = getPendingDeletions()
        current.formUnion(names)
        UserDefaults.standard.set(Array(current), forKey: pendingDeletionsKey)
    }
    
    private func removePendingDeletions(_ names: [String]) {
        var current = getPendingDeletions()
        current.subtract(names)
        UserDefaults.standard.set(Array(current), forKey: pendingDeletionsKey)
    }
    
    /// Flushes any previously queued deletions that may have failed while offline
    func flushPendingDeletions() async {
        let pending = Array(getPendingDeletions())
        guard !pending.isEmpty else { return }
        print("[iOS CloudKit] Flushing \(pending.count) pending deletions from queue...")
        try? await performCloudDeletion(recordNames: pending)
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
            breedImage.isSyncedToCloud = true
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
    
    /// Public entry point for deleting records from CloudKit
    func deleteCloudMedia(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        addPendingDeletions(recordNames)
        try await performCloudDeletion(recordNames: recordNames)
    }
    
    /// Performs deletion on CloudKit database with fallback and .unknownItem tolerance
    private func performCloudDeletion(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
        
        var successfulDeletions: [String] = []
        
        do {
            let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs)
            for (recID, result) in deleteResults {
                switch result {
                case .success:
                    successfulDeletions.append(recID.recordName)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        // Already gone from CloudKit, treat as deleted
                        successfulDeletions.append(recID.recordName)
                    } else {
                        print("[iOS CloudKit] Failed to delete record \(recID.recordName): \(error)")
                    }
                }
            }
        } catch {
            print("[iOS CloudKit] Batch deletion error: \(error), falling back to individual deletes...")
            for id in recordIDs {
                do {
                    _ = try await database.deleteRecord(withID: id)
                    successfulDeletions.append(id.recordName)
                } catch {
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        // Already gone from CloudKit
                        successfulDeletions.append(id.recordName)
                    } else {
                        print("[iOS CloudKit] Individual delete failed for \(id.recordName): \(error)")
                    }
                }
            }
        }
        
        if !successfulDeletions.isEmpty {
            removePendingDeletions(successfulDeletions)
            self.backedUpItemCount = max(0, self.backedUpItemCount - successfulDeletions.count)
            print("[iOS CloudKit] Successfully deleted \(successfulDeletions.count)/\(recordNames.count) records from CloudKit.")
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
    
    // MARK: - Sync with Local SwiftData (Two-Way Deletion & Upload Reconciliation)
    
    func syncWithLocalDatabase(modelContext: ModelContext) async {
        // 1. Flush any pending offline deletions first
        await flushPendingDeletions()
        
        // 2. Fetch current records from CloudKit
        guard let records = try? await fetchCloudMedia() else {
            print("[iOS CloudKit] Aborting local sync: could not fetch records from CloudKit.")
            return
        }
        
        // Index CloudKit records by lowercase UUID
        var cloudRecordIDs = Set<String>()
        for record in records {
            let idString = (record["mediaId"] as? String)
                ?? (record["localID"] as? String)
                ?? record.recordID.recordName
            cloudRecordIDs.insert(idString.lowercased())
        }
        
        // Fetch all existing local images
        let existingDescriptor = FetchDescriptor<BreedImage>()
        let existingImages = (try? modelContext.fetch(existingDescriptor)) ?? []
        let existingIDs = Set(existingImages.map { $0.id.uuidString.lowercased() })
        
        let breedDescriptor = FetchDescriptor<DogBreed>()
        let allBreeds = (try? modelContext.fetch(breedDescriptor)) ?? []
        var breedDict: [String: DogBreed] = [:]
        for b in allBreeds {
            breedDict[b.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = b
        }
        
        var downloadedCount = 0
        var deletedLocalCount = 0
        var uploadedLocalCount = 0
        
        // 3. Download records from CloudKit that don't exist locally
        for record in records {
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
            
            let rawBreedName = (record["breedName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let breedName = (rawBreedName?.isEmpty == false) ? rawBreedName! : "Unknown Breed"
            
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
            let key = breedName.lowercased()
            if let existing = breedDict[key] {
                breed = existing
            } else {
                let newBreed = DogBreed(name: breedName)
                modelContext.insert(newBreed)
                breedDict[key] = newBreed
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
                breed: breed,
                isSyncedToCloud: true
            )
            modelContext.insert(newEntry)
            breed.images.append(newEntry)
            downloadedCount += 1
        }
        
        // 4. Reconcile local images:
        //    - If isSyncedToCloud is true but missing from CloudKit -> It was deleted in CloudKit (delete locally).
        //    - If isSyncedToCloud is false and missing from CloudKit -> It was created locally offline (upload to CloudKit).
        for localImage in existingImages {
            let localKey = localImage.id.uuidString.lowercased()
            if cloudRecordIDs.contains(localKey) {
                localImage.isSyncedToCloud = true
            } else {
                if localImage.isSyncedToCloud {
                    // Record was previously in CloudKit, now deleted -> Purge locally
                    if let breed = localImage.breed,
                       let idx = breed.images.firstIndex(where: { $0.id == localImage.id }) {
                        breed.images.remove(at: idx)
                    }
                    modelContext.delete(localImage)
                    deletedLocalCount += 1
                } else {
                    // Newly captured item waiting for upload
                    let bName = localImage.breed?.name ?? "Unknown Breed"
                    if let _ = try? await uploadBreedMedia(breedImage: localImage, breedName: bName) {
                        localImage.isSyncedToCloud = true
                        uploadedLocalCount += 1
                    }
                }
            }
        }
        
        do {
            try modelContext.save()
            self.backedUpItemCount = records.count + uploadedLocalCount
            self.syncState = .synced(Date())
            self.lastSyncDate = Date()
            print("[iOS CloudKit] Sync completed: \(downloadedCount) downloaded, \(deletedLocalCount) deleted locally, \(uploadedLocalCount) uploaded.")
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
