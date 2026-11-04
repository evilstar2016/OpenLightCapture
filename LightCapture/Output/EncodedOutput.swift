import Foundation
import UniformTypeIdentifiers

enum CaptureFileFormat: String {
    case png, gif, mp4

    var contentType: UTType {
        switch self {
        case .png: .png
        case .gif: .gif
        case .mp4: .mpeg4Movie
        }
    }
}

enum VideoSaveOutcome {
    case saved(URL)
    case cancelled
    case failed(String)
}

enum GIFDeliveryOutcome {
    case completed
    case cancelled
    case failed(savedURL: URL?, message: String)
}
