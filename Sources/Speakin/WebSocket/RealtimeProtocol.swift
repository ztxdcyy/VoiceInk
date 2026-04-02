import Foundation

// MARK: - Delegate Protocol

protocol RealtimeAPIClientDelegate: AnyObject {
    func realtimeClientDidConnect(_ client: RealtimeAPIClient)
    func realtimeClientDidDisconnect(_ client: RealtimeAPIClient, reason: String)
    func realtimeClient(_ client: RealtimeAPIClient, didCompleteTranscript text: String)
    func realtimeClientDidFinishResponse(_ client: RealtimeAPIClient)
    func realtimeClient(_ client: RealtimeAPIClient, didEncounterError error: Error)
    func realtimeClientSessionReady(_ client: RealtimeAPIClient)
}
