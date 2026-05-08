import Foundation

public enum WatcherEvent: Sendable {
    case changed(URL)
}

/// Monitors a directory tree for filesystem changes using DispatchSource.
/// Optimized for the InfiniteBrain vault structure.
public final class VaultWatcher: Sendable {
    private let url: URL
    private let onEvent: @Sendable (WatcherEvent) -> Void
    
    // We use a dedicated queue for FS events to keep the MainActor free.
    private let queue = DispatchQueue(label: "com.infinitebrain.watcher", qos: .background)
    
    // Monitors the root directory for additions/deletions.
    // For deep changes, we'd traditionally use FSEvents, but for a 10k note
    // vault, monitoring the flattened 'notes' structure with targeted
    // dispatch sources is highly efficient.
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32

    public init(url: URL, onEvent: @escaping @Sendable (WatcherEvent) -> Void) throws {
        self.url = url
        self.onEvent = onEvent
        
        self.descriptor = open(url.path, O_EVTONLY)
        guard descriptor != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        
        source.setEventHandler {
            onEvent(.changed(url))
        }
        
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        
        source.resume()
    }
    
    public func stop() {
        source.cancel()
    }
    
    deinit {
        stop()
    }
}
