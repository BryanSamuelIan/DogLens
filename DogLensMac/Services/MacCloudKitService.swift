import Foundation
import CloudKit
import SwiftData
import AppKit

enum MacSyncStatus: Equatable {
    case idle
    case syncing
    case success(String)
    case error(String)
}

@Observable
@MainActor
final class MacCloudKitService {
    static let shared = MacCloudKitService()

    private let container = CKContainer(identifier: "iCloud.DogLens")
    private var privateDB: CKDatabase {
        container.privateCloudDatabase
    }

    var syncStatus: MacSyncStatus = .idle
    var isAvailable: Bool = false

    private init() {}

    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            self.isAvailable = (status == .available)
        } catch {
            print("iCloud account status check failed on Mac: \(error)")
            self.isAvailable = false
        }
    }

    // MARK: - Sync All Records from iCloud to SwiftData
    func syncFromCloud(modelContext: ModelContext) async {
        guard isAvailable else { return }
        syncStatus = .syncing

        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "BreedMedia", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let (results, _) = try await privateDB.records(matching: query)

            var downloadedCount = 0

            // Fetch existing images to prevent duplication
            let existingDescriptor = FetchDescriptor<BreedImage>()
            let existingImages = try modelContext.fetch(existingDescriptor)
            let existingIDs = Set(existingImages.map { $0.id.uuidString })

            let breedDescriptor = FetchDescriptor<DogBreed>()
            let allBreeds = try modelContext.fetch(breedDescriptor)
            var breedDict: [String: DogBreed] = [:]
            for b in allBreeds {
                breedDict[b.name.lowercased()] = b
            }

            for (_, recordResult) in results {
                guard let record = try? recordResult.get() else { continue }
                guard let idString = record["localID"] as? String,
                      let uuid = UUID(uuidString: idString) else { continue }

                if existingIDs.contains(idString) {
                    continue
                }

                let breedName = record["breedName"] as? String ?? "Unknown"
                let confidence = record["confidence"] as? Double ?? 0.0
                let isVideo = (record["isVideo"] as? Int64 ?? 0) == 1
                let detectionDate = record["detectionDate"] as? Date ?? Date()

                var imageData = Data()
                var annotatedImageData: Data?

                if let asset = record["imageAsset"] as? CKAsset,
                   let fileURL = asset.fileURL,
                   let data = try? Data(contentsOf: fileURL) {
                    imageData = data
                }

                if let asset = record["annotatedImageAsset"] as? CKAsset,
                   let fileURL = asset.fileURL,
                   let data = try? Data(contentsOf: fileURL) {
                    annotatedImageData = data
                }

                guard !imageData.isEmpty else { continue }

                // Find or create breed
                let breed: DogBreed
                if let existing = breedDict[breedName.lowercased()] {
                    breed = existing
                } else {
                    let newBreed = DogBreed(name: breedName)
                    modelContext.insert(newBreed)
                    breedDict[breedName.lowercased()] = newBreed
                    breed = newBreed
                }

                let newImage = BreedImage(
                    id: uuid,
                    imageData: imageData,
                    annotatedImageData: annotatedImageData,
                    isVideo: isVideo,
                    detectionDate: detectionDate,
                    confidence: confidence,
                    breed: breed
                )
                modelContext.insert(newImage)
                breed.images.append(newImage)
                downloadedCount += 1
            }

            try modelContext.save()
            syncStatus = .success(downloadedCount > 0 ? "Synced \(downloadedCount) new items" : "Up to date")
        } catch {
            print("CloudKit sync error on Mac: \(error)")
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Upload New Item to iCloud
    func uploadBreedImage(_ breedImage: BreedImage, breedName: String) async {
        do {
            let recordID = CKRecord.ID(recordName: breedImage.id.uuidString)
            let record = CKRecord(recordType: "BreedMedia", recordID: recordID)

            record["localID"] = breedImage.id.uuidString as CKRecordValue
            record["breedName"] = breedName as CKRecordValue
            record["confidence"] = breedImage.confidence as CKRecordValue
            record["isVideo"] = (breedImage.isVideo ? 1 : 0) as CKRecordValue
            record["detectionDate"] = breedImage.detectionDate as CKRecordValue

            let tempDir = FileManager.default.temporaryDirectory
            let imageURL = tempDir.appendingPathComponent("upload_img_\(breedImage.id.uuidString).jpg")
            try breedImage.imageData.write(to: imageURL)
            record["imageAsset"] = CKAsset(fileURL: imageURL)

            if let annotated = breedImage.annotatedImageData {
                let annotatedURL = tempDir.appendingPathComponent("upload_ann_\(breedImage.id.uuidString).jpg")
                try annotated.write(to: annotatedURL)
                record["annotatedImageAsset"] = CKAsset(fileURL: annotatedURL)
            }

            _ = try await privateDB.save(record)
            print("Uploaded BreedMedia \(breedImage.id) to CloudKit from Mac")
        } catch {
            print("Failed to upload to CloudKit from Mac: \(error)")
        }
    }
}
