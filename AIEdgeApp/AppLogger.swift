//
//  AppLogger.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 04.03.2026.
//

import Foundation

enum AppLogger {
    static func clearTemporaryDirectory() {
        print("🧹 [AppLogger] Cleaning up temporary directory...")
        let fileManager = FileManager.default
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil, options: [])
            var deletedCount = 0
            var deletedSize: Int64 = 0
            
            for itemURL in contents {
                // Specifically target CFNetworkDownload or any .tmp files
                if itemURL.lastPathComponent.hasPrefix("CFNetworkDownload") || itemURL.pathExtension == "tmp" {
                    let fileSize = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    try fileManager.removeItem(at: itemURL)
                    deletedCount += 1
                    deletedSize += Int64(fileSize)
                }
            }
            
            let sizeStr = ByteCountFormatter.string(fromByteCount: deletedSize, countStyle: .file)
            print("✅ [AppLogger] Deleted \(deletedCount) temporary files (\(sizeStr)).")
        } catch {
            print("❌ [AppLogger] Failed to clear temporary directory: \(error.localizedDescription)")
        }
    }

    static func logDownloadedFiles() {
        print("--------------------------------------------------")
        print("🚀 [AppLogger] Scanning for downloaded models and files...")
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ [AppLogger] Could not access documents directory.")
            return
        }
        
        // 1. Scan EVERY top-level directory in Documents
        scanRoot(documentsURL, label: "Documents")
        
        // 2. Scan EVERY top-level directory in Application Support
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            scanRoot(appSupportURL, label: "Application Support")
        }
        
        // 3. Scan EVERY top-level directory in Caches
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
             scanRoot(cachesURL, label: "Caches")
        }

        // 4. Scan Temporary directory
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        scanRoot(tmpURL, label: "Temporary")

        // 5. Specifically look for hidden .cache in Documents
        let dotCacheURL = documentsURL.appending(path: ".cache")
        if fileManager.fileExists(atPath: dotCacheURL.path()) {
            scanRoot(dotCacheURL, label: "Hidden .cache")
        }
        
        print("\n--------------------------------------------------")
    }
    
    private static func scanRoot(_ url: URL, label: String) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path()) else {
            print("\n📂 [\(label)] Path: \(url.path())")
            print("   (Directory does not exist)")
            return
        }
        
        print("\n📂 [\(label)] Path: \(url.path())")
        let totalSize = scanDirectory(url, label: label)
        let totalSizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        print("📊 [\(label) Total Size]: \(totalSizeStr)")
    }
    
    @discardableResult
    private static func scanDirectory(_ url: URL, label: String, indent: String = "   ") -> Int64 {
        let fileManager = FileManager.default
        var totalFolderSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
            
            if contents.isEmpty {
                print("\(indent)(Directory is empty)")
                return 0
            }
            
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = resourceValues.isDirectory ?? false
                
                if isDirectory {
                    print("\(indent)📁 \(itemURL.lastPathComponent)/")
                    let subFolderSize = scanDirectory(itemURL, label: label, indent: indent + "  ")
                    totalFolderSize += subFolderSize
                    if subFolderSize > 0 {
                        let subFolderSizeStr = ByteCountFormatter.string(fromByteCount: subFolderSize, countStyle: .file)
                        print("\(indent)  ↳ 📦 Total: \(subFolderSizeStr)")
                    }
                } else {
                    let fileSize = Int64(resourceValues.fileSize ?? 0)
                    totalFolderSize += fileSize
                    let fileSizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                    print("\(indent)📄 \(itemURL.lastPathComponent) (\(fileSizeString))")
                }
            }
        } catch {
            print("\(indent)❌ Error scanning: \(error.localizedDescription)")
        }
        
        return totalFolderSize
    }
}
