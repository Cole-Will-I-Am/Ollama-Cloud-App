import Foundation

/// Exports a project's files to a .zip archive using AppleArchive/System frameworks.
enum ProjectExporter {
    enum ExportError: LocalizedError {
        case noFiles
        case writeFailed(String)
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFiles: return "Project has no files to export."
            case .writeFailed(let msg): return "Failed to write files: \(msg)"
            case .zipFailed(let msg): return "Failed to create zip: \(msg)"
            }
        }
    }

    static func exportAsZip(project: Project) throws -> URL {
        let files = project.files.filter { !$0.isDirectory }
        guard !files.isEmpty else { throw ExportError.noFiles }

        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("seer-export-\(UUID().uuidString)")
        let projectDir = tempBase.appendingPathComponent(project.name)

        // Write all files to a temp directory
        for file in files {
            let filePath = projectDir.appendingPathComponent(file.path)
            let parentDir = filePath.deletingLastPathComponent()

            do {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                try file.content.write(to: filePath, atomically: true, encoding: .utf8)
            } catch {
                // Clean up on failure
                try? fm.removeItem(at: tempBase)
                throw ExportError.writeFailed(error.localizedDescription)
            }
        }

        // Create zip using the NSFileCoordinator trick (works on both iOS and macOS)
        let zipURL = tempBase.appendingPathComponent("\(project.name).zip")

        #if os(macOS)
        // Use /usr/bin/zip on macOS for reliable zip creation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", zipURL.path, project.name]
        process.currentDirectoryURL = tempBase
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ExportError.zipFailed("zip exited with status \(process.terminationStatus)")
            }
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.zipFailed(error.localizedDescription)
        }
        #else
        // On iOS, use the NSFileCoordinator forUploading trick to create a zip from a directory
        var coordinatorError: NSError?
        var zipResult: URL?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: projectDir,
            options: .forUploading,
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
                zipResult = zipURL
            } catch {
                // Will be handled below
            }
        }
        if let coordinatorError {
            throw ExportError.zipFailed(coordinatorError.localizedDescription)
        }
        guard zipResult != nil else {
            throw ExportError.zipFailed("Failed to create zip archive")
        }
        #endif

        // Clean up the unzipped directory, keep only the zip
        try? fm.removeItem(at: projectDir)

        return zipURL
    }
}
