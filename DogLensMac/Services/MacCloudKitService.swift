import Foundation
import CloudKit
import SwiftData
import AppKit

enum MacSyncStatus: Equatable {
    case idle
    case syncing
    case success(String)
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return "iCloud Ready"
        case .syncing:
            return "Syncing with iCloud…"
        case .success(let msg):
            return msg
        case .error(let msg):
            return "Sync Error: \(msg)"
        }
    }
}

@Observable
@MainActor
final class MacCloudKitService {
    static let shared = MacCloudKitService()

    public static let recordType = "BreedMedia"

    private let container = CKContainer(identifier: "iCloud.DogLens")
    private var privateDB: CKDatabase {
        container.privateCloudDatabase
    }

    var syncStatus: MacSyncStatus = .idle
    var isAvailable: Bool = true
    var backedUpItemCount: Int = 0

    // Persistent Pending Deletions Key
    private let pendingDeletionsKey = "com.doglens.mac.pendingCloudDeletions"

    private init() {}

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
        print("[Mac CloudKit] Flushing \(pending.count) pending deletions from queue...")
        await performCloudDeletion(recordNames: pending)
    }

    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            self.isAvailable = (status == .available || status == .couldNotDetermine)
            print("Mac iCloud Account Status: \(status.rawValue) (isAvailable=\(isAvailable))")
            if self.isAvailable {
                await refreshCloudItemCount()
            }
        } catch {
            print("iCloud account status check failed on Mac: \(error)")
            // Don't permanently block, let subsequent network requests try
            self.isAvailable = true
        }
    }

    func refreshCloudItemCount() async {
        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)
            let (results, _) = try await privateDB.records(matching: query)
            self.backedUpItemCount = results.count
        } catch {
            print("Failed to refresh cloud item count on Mac: \(error)")
        }
    }

    // MARK: - Sync All Records between iCloud and SwiftData (Two-Way Deletion & Upload Sync)
    func syncWithLocalDatabase(modelContext: ModelContext) async {
        await syncFromCloud(modelContext: modelContext)
    }

    func syncFromCloud(modelContext: ModelContext) async {
        syncStatus = .syncing

        // 1. Flush any pending offline deletions first
        await flushPendingDeletions()

        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)

            var (matchResults, cursor) = try await privateDB.records(matching: query)

            var records: [CKRecord] = []
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    records.append(record)
                }
            }

            while let currentCursor = cursor {
                let (nextResults, nextCursor) = try await privateDB.records(continuingMatchFrom: currentCursor)
                for (_, result) in nextResults {
                    if case .success(let record) = result {
                        records.append(record)
                    }
                }
                cursor = nextCursor
            }

            var downloadedCount = 0
            var deletedLocalCount = 0
            var uploadedLocalCount = 0

            // Fetch existing images to prevent duplication
            let existingDescriptor = FetchDescriptor<BreedImage>()
            let existingImages = (try? modelContext.fetch(existingDescriptor)) ?? []
            let existingIDs = Set(existingImages.map { $0.id.uuidString.lowercased() })

            // Index existing breeds
            let breedDescriptor = FetchDescriptor<DogBreed>()
            let allBreeds = (try? modelContext.fetch(breedDescriptor)) ?? []
            var breedDict: [String: DogBreed] = [:]
            for b in allBreeds {
                breedDict[b.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = b
            }

            var cloudRecordIDs = Set<String>()

            // 2. Download records from CloudKit that don't exist locally
            for record in records {
                let idString = (record["mediaId"] as? String)
                    ?? (record["localID"] as? String)
                    ?? record.recordID.recordName

                cloudRecordIDs.insert(idString.lowercased())

                guard let uuid = UUID(uuidString: idString) else { continue }

                if existingIDs.contains(uuid.uuidString.lowercased()) {
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
                if let asset = record["imageAsset"] as? CKAsset,
                   let fileURL = asset.fileURL,
                   let data = try? Data(contentsOf: fileURL) {
                    imageData = data
                }

                var annotatedImageData: Data? = nil
                if let asset = record["annotatedImageAsset"] as? CKAsset,
                   let fileURL = asset.fileURL {
                    annotatedImageData = try? Data(contentsOf: fileURL)
                }

                var videoData: Data? = nil
                if let asset = record["videoAsset"] as? CKAsset,
                   let fileURL = asset.fileURL {
                    videoData = try? Data(contentsOf: fileURL)
                }

                var annotatedVideoData: Data? = nil
                if let asset = record["annotatedVideoAsset"] as? CKAsset,
                   let fileURL = asset.fileURL {
                    annotatedVideoData = try? Data(contentsOf: fileURL)
                }

                guard !imageData.isEmpty else { continue }

                // Find or create breed
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

                let newImage = BreedImage(
                    id: uuid,
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
                modelContext.insert(newImage)
                breed.images.append(newImage)
                downloadedCount += 1
            }

            // 3. Reconcile local images:
            //    - If isSyncedToCloud is true but missing from CloudKit -> It was deleted in CloudKit (delete locally).
            //    - If isSyncedToCloud is false and missing from CloudKit -> It was created locally offline (upload to CloudKit).
            for localImage in existingImages {
                let localKey = localImage.id.uuidString.lowercased()
                if cloudRecordIDs.contains(localKey) {
                    localImage.isSyncedToCloud = true
                } else {
                    if localImage.isSyncedToCloud {
                        // Deleted remotely -> Delete locally
                        if let breed = localImage.breed,
                           let idx = breed.images.firstIndex(where: { $0.id == localImage.id }) {
                            breed.images.remove(at: idx)
                        }
                        modelContext.delete(localImage)
                        deletedLocalCount += 1
                    } else {
                        // Local pending upload
                        let bName = localImage.breed?.name ?? "Unknown Breed"
                        await uploadBreedImage(localImage, breedName: bName)
                        if localImage.isSyncedToCloud {
                            uploadedLocalCount += 1
                        }
                    }
                }
            }

            try? modelContext.save()
            self.backedUpItemCount = records.count + uploadedLocalCount
            self.isAvailable = true

            let statusMessage: String
            if downloadedCount > 0 || deletedLocalCount > 0 || uploadedLocalCount > 0 {
                statusMessage = "Synced: +\(downloadedCount) / -\(deletedLocalCount) / ↑\(uploadedLocalCount)"
            } else {
                statusMessage = "iCloud Up to Date"
            }

            syncStatus = .success(statusMessage)
            print("CloudKit sync finished on Mac: Downloaded \(downloadedCount), Deleted \(deletedLocalCount), Uploaded \(uploadedLocalCount), Total in cloud \(records.count).")
        } catch {
            print("CloudKit sync error on Mac: \(error)")
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Upload Item to iCloud
    func uploadBreedImage(_ breedImage: BreedImage, breedName: String) async {
        do {
            let recordID = CKRecord.ID(recordName: breedImage.id.uuidString)
            let record = CKRecord(recordType: Self.recordType, recordID: recordID)

            // Write both mediaId and localID for cross-compatibility
            record["mediaId"] = breedImage.id.uuidString as CKRecordValue
            record["localID"] = breedImage.id.uuidString as CKRecordValue
            record["breedName"] = breedName as CKRecordValue
            record["confidence"] = breedImage.confidence as CKRecordValue
            record["isVideo"] = (breedImage.isVideo ? 1 : 0) as CKRecordValue
            record["detectionDate"] = breedImage.detectionDate as CKRecordValue

            var tempFiles: [URL] = []

            // Save Original Image Asset
            if let imgURL = createTempFile(data: breedImage.imageData, ext: "jpg") {
                record["imageAsset"] = CKAsset(fileURL: imgURL)
                tempFiles.append(imgURL)
            }

            // Save Annotated Image Asset
            if let annotated = breedImage.annotatedImageData,
               let annURL = createTempFile(data: annotated, ext: "jpg") {
                record["annotatedImageAsset"] = CKAsset(fileURL: annURL)
                tempFiles.append(annURL)
            }

            // Save Video Asset
            if let vidData = breedImage.videoData,
               let vidURL = createTempFile(data: vidData, ext: "mp4") {
                record["videoAsset"] = CKAsset(fileURL: vidURL)
                tempFiles.append(vidURL)
            }

            // Save Annotated Video Asset
            if let annVidData = breedImage.annotatedVideoData,
               let annVidURL = createTempFile(data: annVidData, ext: "mp4") {
                record["annotatedVideoAsset"] = CKAsset(fileURL: annVidURL)
                tempFiles.append(annVidURL)
            }

            _ = try await privateDB.save(record)
            breedImage.isSyncedToCloud = true
            self.backedUpItemCount += 1
            self.syncStatus = .success("Saved to iCloud")
            print("Successfully uploaded BreedMedia \(breedImage.id) to CloudKit from Mac")

            // Clean up temp files
            for url in tempFiles {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to upload to CloudKit from Mac: \(error)")
            self.syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Delete Cloud Media

    /// Public entry point for deleting records from CloudKit on Mac
    func deleteCloudMedia(recordNames: [String]) async {
        guard !recordNames.isEmpty else { return }
        addPendingDeletions(recordNames)
        await performCloudDeletion(recordNames: recordNames)
    }

    private func performCloudDeletion(recordNames: [String]) async {
        guard !recordNames.isEmpty else { return }
        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }

        var successfulDeletions: [String] = []

        do {
            let (_, deleteResults) = try await privateDB.modifyRecords(saving: [], deleting: recordIDs)
            for (recID, result) in deleteResults {
                switch result {
                case .success:
                    successfulDeletions.append(recID.recordName)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        // Already gone from CloudKit
                        successfulDeletions.append(recID.recordName)
                    } else {
                        print("Failed to delete record \(recID.recordName) on Mac: \(error)")
                    }
                }
            }
        } catch {
            print("Mac CloudKit batch deletion error: \(error), falling back to individual deletes...")
            for id in recordIDs {
                do {
                    _ = try await privateDB.deleteRecord(withID: id)
                    successfulDeletions.append(id.recordName)
                } catch {
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        // Already gone from CloudKit
                        successfulDeletions.append(id.recordName)
                    } else {
                        print("Mac individual delete failed for \(id.recordName): \(error)")
                    }
                }
            }
        }

        if !successfulDeletions.isEmpty {
            removePendingDeletions(successfulDeletions)
            self.backedUpItemCount = max(0, self.backedUpItemCount - successfulDeletions.count)
            print("Successfully deleted \(successfulDeletions.count)/\(recordNames.count) records from CloudKit on Mac")
        }
    }

    func deleteCloudMedia(recordName: String) async {
        await deleteCloudMedia(recordNames: [recordName])
    }

    private func createTempFile(data: Data, ext: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("doglens_\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}
