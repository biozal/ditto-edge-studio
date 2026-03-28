/// The source tab selection for the Logging screen.
///
/// Stored in `DittoLogCaptureService.shared` so the selection persists
/// across navigation (the view is recreated each time it appears).
enum LoggingSourceTab: String, CaseIterable {
    case dittoSDK = "Ditto SDK"
    case application = "App Logs"
    case imported = "Imported"
    case transportConditions = "Transport Conditions"
    case connectionRequests = "Connection Requests"
}
