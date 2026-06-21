import CoreMedia
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureFrameValidator {
    static func isWritableFrameStatus(_ rawStatus: Int?) -> Bool {
        guard let rawStatus, let status = SCFrameStatus(rawValue: rawStatus) else {
            return false
        }

        return status == .complete
    }

    static func isWritableVideoFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let rawStatus = attachments[SCStreamFrameInfo.status] as? Int
        else {
            return false
        }

        return isWritableFrameStatus(rawStatus)
    }
}
