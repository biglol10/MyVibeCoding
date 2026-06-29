import Foundation

public protocol VolumeListing: Sendable {
    func mountedVolumes() async throws -> [MountedVolume]
}

public struct VolumeService: VolumeListing, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func mountedVolumes() async throws -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey,
            .isReadableKey
        ]

        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        let volumes = urls.compactMap { url -> MountedVolume? in
            let values = try? url.resourceValues(forKeys: keys)
            let isBrowsable = values?.volumeIsBrowsable ?? true
            guard isBrowsable else {
                return nil
            }

            return MountedVolume(
                url: url,
                name: values?.volumeName,
                isLocal: values?.volumeIsLocal ?? true,
                isRemovable: values?.volumeIsRemovable ?? false,
                isBrowsable: isBrowsable,
                isReadable: values?.isReadable ?? fileManager.isReadableFile(atPath: url.path)
            )
        }

        return MountedVolume.sortedForSidebar(volumes)
    }
}
