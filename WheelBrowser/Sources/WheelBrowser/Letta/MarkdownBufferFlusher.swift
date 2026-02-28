import Foundation

/// Detects complete markdown structures that represent safe flush points
/// for streaming content. This reduces UI updates while ensuring meaningful
/// visual progress during LLM streaming.
///
/// Delegates to `StreamingResponseHandler.isMarkdownFlushPoint` with a
/// hardcoded 200-character buffer threshold matching the original behavior.
struct MarkdownBufferFlusher {

    /// Determines whether the pending buffer content should be flushed to the UI.
    ///
    /// - Parameter buffer: The accumulated text that has not yet been flushed.
    /// - Returns: `true` if the buffer ends at a natural markdown boundary.
    func shouldFlush(_ buffer: String) -> Bool {
        StreamingResponseHandler.isMarkdownFlushPoint(buffer, maxBufferSize: 200)
    }
}
