import Foundation

// MARK: - Delegate Protocol

protocol RealtimeAPIClientDelegate: AnyObject {
    func realtimeClientDidConnect(_ client: RealtimeAPIClient)
    func realtimeClientDidDisconnect(_ client: RealtimeAPIClient, reason: String)
    /// Called during recording with live input_audio_transcription delta (real-time, may be partial/unstable)
    func realtimeClient(_ client: RealtimeAPIClient, didReceiveLiveTranscriptDelta delta: String)
    /// Called after Fn release with the final committed transcript text
    func realtimeClient(_ client: RealtimeAPIClient, didCompleteTranscript text: String)
    func realtimeClientDidFinishResponse(_ client: RealtimeAPIClient)
    func realtimeClient(_ client: RealtimeAPIClient, didEncounterError error: Error)
    func realtimeClientSessionReady(_ client: RealtimeAPIClient)
}
