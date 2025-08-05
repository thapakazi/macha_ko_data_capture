/*
See LICENSE folder for this sample's licensing information.

Abstract:
Data model for capture sessions and their associated files.
*/

import Foundation
import UIKit
import Compression

struct CaptureData: Codable {
    let id: String
    let timestamp: TimeInterval
    let date: Date
    
    // File paths
    let calibrationJSONPath: String?
    let depthTIFFPath: String?
    let depthBinaryPath: String?
    let metadataJSONPath: String?
    let rgbImagePath: String?
    let jetImagePath: String?
    
    // Calibration data
    let intrinsicMatrix: IntrinsicMatrix?
    let extrinsicMatrix: ExtrinsicMatrix?
    let videoDimensions: Dimensions
    let referenceDimensions: Dimensions
    let pixelSize: Double
    let lensDistortionCenter: Point
    
    init(timestamp: TimeInterval,
         calibrationJSONPath: String? = nil,
         depthTIFFPath: String? = nil,
         depthBinaryPath: String? = nil,
         metadataJSONPath: String? = nil,
         rgbImagePath: String? = nil,
         jetImagePath: String? = nil,
         intrinsicMatrix: IntrinsicMatrix? = nil,
         extrinsicMatrix: ExtrinsicMatrix? = nil,
         videoDimensions: Dimensions,
         referenceDimensions: Dimensions,
         pixelSize: Double,
         lensDistortionCenter: Point) {
        
        self.id = "capture_\(Int(timestamp))"
        self.timestamp = timestamp
        self.date = Date(timeIntervalSince1970: timestamp)
        self.calibrationJSONPath = calibrationJSONPath
        self.depthTIFFPath = depthTIFFPath
        self.depthBinaryPath = depthBinaryPath
        self.metadataJSONPath = metadataJSONPath
        self.rgbImagePath = rgbImagePath
        self.jetImagePath = jetImagePath
        self.intrinsicMatrix = intrinsicMatrix
        self.extrinsicMatrix = extrinsicMatrix
        self.videoDimensions = videoDimensions
        self.referenceDimensions = referenceDimensions
        self.pixelSize = pixelSize
        self.lensDistortionCenter = lensDistortionCenter
    }
}

struct IntrinsicMatrix: Codable {
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let fx_original: Double
    let fy_original: Double
    let cx_original: Double
    let cy_original: Double
}

struct ExtrinsicMatrix: Codable {
    let column0: [Double]
    let column1: [Double]
    let column2: [Double]
    let column3: [Double]
    let description: String
}

struct Dimensions: Codable {
    let width: Int
    let height: Int
}

struct Point: Codable {
    let x: Double
    let y: Double
}

// MARK: - CaptureManager
class CaptureManager {
    static let shared = CaptureManager()
    private var captures: [CaptureData] = []
    
    private let documentsURL: URL
    private let capturesFileName = "captures.json"
    
    private init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadCaptures()
    }
    
    func addCapture(_ capture: CaptureData) {
        captures.append(capture)
        captures.sort { $0.timestamp > $1.timestamp } // Most recent first
        saveCaptures()
    }
    
    func getAllCaptures() -> [CaptureData] {
        return captures
    }
    
    func getCapture(withID id: String) -> CaptureData? {
        return captures.first { $0.id == id }
    }
    
    func deleteCapture(withID id: String) {
        // Find the capture to get file paths
        if let capture = captures.first(where: { $0.id == id }) {
            deleteFiles(for: capture)
        }
        
        captures.removeAll { $0.id == id }
        saveCaptures()
    }
    
    private func deleteFiles(for capture: CaptureData) {
        let filePaths = [
            capture.calibrationJSONPath,
            capture.depthTIFFPath,
            capture.depthBinaryPath,
            capture.metadataJSONPath,
            capture.rgbImagePath,
            capture.jetImagePath
        ]
        
        // Delete individual files
        for path in filePaths {
            if let path = path {
                try? FileManager.default.removeItem(atPath: path)
                print("Deleted file: \(path)")
            }
        }
        
        // Delete the entire capture folder if it exists
        if let calibrationPath = capture.calibrationJSONPath,
           let folderURL = URL(string: calibrationPath)?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: folderURL)
            print("Deleted capture folder: \(folderURL.path)")
        }
        
        // Also delete README.md if it exists
        if let calibrationPath = capture.calibrationJSONPath {
            let folderPath = (calibrationPath as NSString).deletingLastPathComponent
            let readmePath = (folderPath as NSString).appendingPathComponent("README.md")
            try? FileManager.default.removeItem(atPath: readmePath)
        }
    }
    
    private func saveCaptures() {
        let url = documentsURL.appendingPathComponent(capturesFileName)
        do {
            let data = try JSONEncoder().encode(captures)
            try data.write(to: url)
        } catch {
            print("Error saving captures: \(error)")
        }
    }
    
    private func loadCaptures() {
        let url = documentsURL.appendingPathComponent(capturesFileName)
        do {
            let data = try Data(contentsOf: url)
            captures = try JSONDecoder().decode([CaptureData].self, from: data)
        } catch {
            print("Error loading captures (this is normal on first run): \(error)")
            captures = []
        }
    }
    
    // Utility functions
    func fileExists(at path: String?) -> Bool {
        guard let path = path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    
    func getFileURL(for path: String?) -> URL? {
        guard let path = path else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    func exportAllCaptures() -> URL? {
        guard !captures.isEmpty else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let exportName = "TrueDepth_Export_\(dateFormatter.string(from: Date()))"
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let exportFolder = tempDirectory.appendingPathComponent(exportName)
        
        do {
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: nil)
            
            // Create export summary
            let exportSummary = """
            # TrueDepth Capture Export
            
            **Export Date:** \(Date().description)  
            **Total Captures:** \(captures.count)  
            **Device:** \(UIDevice.current.model) (\(UIDevice.current.systemVersion))
            
            ## Included Captures:
            
            \(captures.map { "- \($0.id) - \(DateFormatter.localizedString(from: $0.date, dateStyle: .medium, timeStyle: .short))" }.joined(separator: "\n"))
            
            ---
            *Generated by TrueDepth Streamer*
            """
            
            let summaryFile = exportFolder.appendingPathComponent("Export_Summary.md")
            try exportSummary.write(to: summaryFile, atomically: true, encoding: .utf8)
            
            // Copy all capture folders with all files
            for capture in captures {
                if let calibrationPath = capture.calibrationJSONPath {
                    let sourceFolder = URL(fileURLWithPath: calibrationPath).deletingLastPathComponent()
                    let destinationFolder = exportFolder.appendingPathComponent(capture.id)
                    
                    do {
                        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: nil)
                        
                        // Copy all files individually to ensure they're included
                        let allPaths = [
                            capture.calibrationJSONPath,
                            capture.depthTIFFPath,
                            capture.depthBinaryPath,
                            capture.metadataJSONPath,
                            capture.rgbImagePath,
                            capture.jetImagePath
                        ]
                        
                        for path in allPaths {
                            if let path = path, FileManager.default.fileExists(atPath: path) {
                                let sourceURL = URL(fileURLWithPath: path)
                                let destURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
                                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                            }
                        }
                        
                        // Copy README.md if it exists
                        let readmeSource = sourceFolder.appendingPathComponent("README.md")
                        if FileManager.default.fileExists(atPath: readmeSource.path) {
                            let readmeDest = destinationFolder.appendingPathComponent("README.md")
                            try? FileManager.default.copyItem(at: readmeSource, to: readmeDest)
                        }
                        
                    } catch {
                        print("Error exporting capture \(capture.id): \(error)")
                    }
                }
            }
            
            // Create a ZIP file of the entire export
            let exportZipName = "\(exportName).zip"
            let exportZipURL = tempDirectory.appendingPathComponent(exportZipName)
            
            if createZipFile(sourceDirectory: exportFolder, zipFileURL: exportZipURL) {
                // Clean up the unzipped folder
                try? FileManager.default.removeItem(at: exportFolder)
                return exportZipURL
            } else {
                return exportFolder // Return folder if ZIP creation fails
            }
            
        } catch {
            print("Error creating export: \(error)")
            return nil
        }
    }
    
    // Create ZIP file for a single capture
    func createZipFile(for capture: CaptureData) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let zipFileName = "\(capture.id).zip"
        let zipFileURL = tempDirectory.appendingPathComponent(zipFileName)
        
        // Remove existing ZIP file if it exists
        try? FileManager.default.removeItem(at: zipFileURL)
        
        // Create a temporary directory for organizing files before zipping
        let tempCaptureDir = tempDirectory.appendingPathComponent("temp_\(capture.id)")
        try? FileManager.default.removeItem(at: tempCaptureDir)
        
        do {
            try FileManager.default.createDirectory(at: tempCaptureDir, withIntermediateDirectories: true, attributes: nil)
            
            // Copy all files to temp directory
            let allPaths = [
                ("calibration.json", capture.calibrationJSONPath),
                ("depth.tiff", capture.depthTIFFPath),
                ("depth.depth", capture.depthBinaryPath),
                ("metadata.json", capture.metadataJSONPath),
                ("rgb_image.jpg", capture.rgbImagePath),
                ("depth_jet.jpg", capture.jetImagePath)
            ]
            
            var copiedFiles = 0
            for (fileName, filePath) in allPaths {
                if let filePath = filePath, FileManager.default.fileExists(atPath: filePath) {
                    let sourceURL = URL(fileURLWithPath: filePath)
                    let destURL = tempCaptureDir.appendingPathComponent(fileName)
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    copiedFiles += 1
                }
            }
            
            // Copy README.md if it exists
            if let calibrationPath = capture.calibrationJSONPath {
                let sourceFolder = URL(fileURLWithPath: calibrationPath).deletingLastPathComponent()
                let readmeSource = sourceFolder.appendingPathComponent("README.md")
                if FileManager.default.fileExists(atPath: readmeSource.path) {
                    let readmeDest = tempCaptureDir.appendingPathComponent("README.md")
                    try? FileManager.default.copyItem(at: readmeSource, to: readmeDest)
                    copiedFiles += 1
                }
            }
            
            if copiedFiles > 0 {
                // Create ZIP file using iOS-compatible method
                let result = createZipFile(sourceDirectory: tempCaptureDir, zipFileURL: zipFileURL)
                
                // Clean up temp directory
                try? FileManager.default.removeItem(at: tempCaptureDir)
                
                return result ? zipFileURL : nil
            }
            
        } catch {
            print("Error creating ZIP file: \(error)")
        }
        
        // Clean up temp directory in case of error
        try? FileManager.default.removeItem(at: tempCaptureDir)
        return nil
    }
    
    private func createZipFile(sourceDirectory: URL, zipFileURL: URL) -> Bool {
        // Create a proper ZIP file using the ZIP format specification
        
        do {
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: zipFileURL)
            
            // Get list of all files in the source directory
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [])
            
            var zipData = Data()
            var centralDirectory = Data()
            var centralDirectoryOffset: UInt32 = 0
            var fileCount: UInt16 = 0
            
            for fileURL in files {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                
                let fileData = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent
                let fileNameData = fileName.data(using: .utf8) ?? Data()
                
                // Calculate CRC32 for the file
                let crc32 = calculateCRC32(for: fileData)
                
                // Local file header
                let localHeaderOffset = UInt32(zipData.count)
                
                // Local file header signature
                zipData.append(Data([0x50, 0x4B, 0x03, 0x04]))
                
                // Version needed to extract (2.0)
                zipData.append(Data([0x14, 0x00]))
                
                // General purpose bit flag
                zipData.append(Data([0x00, 0x00]))
                
                // Compression method (stored - no compression)
                zipData.append(Data([0x00, 0x00]))
                
                // File last modification time & date (use current time)
                let dosDateTime = getCurrentDOSDateTime()
                zipData.append(withUnsafeBytes(of: dosDateTime.time.littleEndian) { Data($0) })
                zipData.append(withUnsafeBytes(of: dosDateTime.date.littleEndian) { Data($0) })
                
                // CRC-32
                zipData.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) })
                
                // Compressed size
                let compressedSize = UInt32(fileData.count)
                zipData.append(withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
                
                // Uncompressed size
                zipData.append(withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
                
                // Filename length
                let filenameLength = UInt16(fileNameData.count)
                zipData.append(withUnsafeBytes(of: filenameLength.littleEndian) { Data($0) })
                
                // Extra field length
                zipData.append(Data([0x00, 0x00]))
                
                // Filename
                zipData.append(fileNameData)
                
                // File data
                zipData.append(fileData)
                
                // Central directory entry
                // Central file header signature
                centralDirectory.append(Data([0x50, 0x4B, 0x01, 0x02]))
                
                // Version made by
                centralDirectory.append(Data([0x14, 0x03]))
                
                // Version needed to extract
                centralDirectory.append(Data([0x14, 0x00]))
                
                // General purpose bit flag
                centralDirectory.append(Data([0x00, 0x00]))
                
                // Compression method
                centralDirectory.append(Data([0x00, 0x00]))
                
                // File last modification time & date
                centralDirectory.append(withUnsafeBytes(of: dosDateTime.time.littleEndian) { Data($0) })
                centralDirectory.append(withUnsafeBytes(of: dosDateTime.date.littleEndian) { Data($0) })
                
                // CRC-32
                centralDirectory.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) })
                
                // Compressed size
                centralDirectory.append(withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
                
                // Uncompressed size
                centralDirectory.append(withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
                
                // Filename length
                centralDirectory.append(withUnsafeBytes(of: filenameLength.littleEndian) { Data($0) })
                
                // Extra field length
                centralDirectory.append(Data([0x00, 0x00]))
                
                // Comment length
                centralDirectory.append(Data([0x00, 0x00]))
                
                // Disk number start
                centralDirectory.append(Data([0x00, 0x00]))
                
                // Internal file attributes
                centralDirectory.append(Data([0x00, 0x00]))
                
                // External file attributes
                centralDirectory.append(Data([0x00, 0x00, 0x00, 0x00]))
                
                // Relative offset of local header
                centralDirectory.append(withUnsafeBytes(of: localHeaderOffset.littleEndian) { Data($0) })
                
                // Filename
                centralDirectory.append(fileNameData)
                
                fileCount += 1
            }
            
            // Store the central directory offset
            centralDirectoryOffset = UInt32(zipData.count)
            
            // Append central directory to zip data
            zipData.append(centralDirectory)
            
            // End of central directory record
            // End of central directory signature
            zipData.append(Data([0x50, 0x4B, 0x05, 0x06]))
            
            // Number of this disk
            zipData.append(Data([0x00, 0x00]))
            
            // Number of the disk with the start of the central directory
            zipData.append(Data([0x00, 0x00]))
            
            // Total number of entries in the central directory on this disk
            zipData.append(withUnsafeBytes(of: fileCount.littleEndian) { Data($0) })
            
            // Total number of entries in the central directory
            zipData.append(withUnsafeBytes(of: fileCount.littleEndian) { Data($0) })
            
            // Size of the central directory
            let centralDirectorySize = UInt32(centralDirectory.count)
            zipData.append(withUnsafeBytes(of: centralDirectorySize.littleEndian) { Data($0) })
            
            // Offset of start of central directory
            zipData.append(withUnsafeBytes(of: centralDirectoryOffset.littleEndian) { Data($0) })
            
            // Comment length
            zipData.append(Data([0x00, 0x00]))
            
            // Write the ZIP data to file
            try zipData.write(to: zipFileURL)
            return true
            
        } catch {
            print("Error creating ZIP file: \(error)")
            return false
        }
    }
    
    private func calculateCRC32(for data: Data) -> UInt32 {
        // Simple CRC32 implementation
        var crc: UInt32 = 0xFFFFFFFF
        
        for byte in data {
            crc = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc = crc >> 1
                }
            }
        }
        
        return crc ^ 0xFFFFFFFF
    }
    
    private func getCurrentDOSDateTime() -> (time: UInt16, date: UInt16) {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        
        // DOS date format: bits 15-9 = year-1980, bits 8-5 = month, bits 4-0 = day
        let year = UInt16((components.year ?? 1980) - 1980)
        let month = UInt16(components.month ?? 1)
        let day = UInt16(components.day ?? 1)
        let dosDate = (year << 9) | (month << 5) | day
        
        // DOS time format: bits 15-11 = hour, bits 10-5 = minute, bits 4-0 = second/2
        let hour = UInt16(components.hour ?? 0)
        let minute = UInt16(components.minute ?? 0)
        let second = UInt16((components.second ?? 0) / 2)
        let dosTime = (hour << 11) | (minute << 5) | second
        
        return (time: dosTime, date: dosDate)
    }
    
    // Alternative method: Return array of individual file URLs for sharing
    func getFilesForSharing(for capture: CaptureData) -> [URL] {
        var fileURLs: [URL] = []
        
        let filePaths = [
            capture.calibrationJSONPath,
            capture.depthTIFFPath,
            capture.depthBinaryPath,
            capture.metadataJSONPath,
            capture.rgbImagePath,
            capture.jetImagePath
        ]
        
        for path in filePaths {
            if let path = path, FileManager.default.fileExists(atPath: path) {
                fileURLs.append(URL(fileURLWithPath: path))
            }
        }
        
        // Also include README.md if it exists
        if let calibrationPath = capture.calibrationJSONPath {
            let folderPath = (calibrationPath as NSString).deletingLastPathComponent
            let readmePath = (folderPath as NSString).appendingPathComponent("README.md")
            if FileManager.default.fileExists(atPath: readmePath) {
                fileURLs.append(URL(fileURLWithPath: readmePath))
            }
        }
        
        return fileURLs
    }
}