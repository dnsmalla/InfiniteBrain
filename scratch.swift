import Vision
let request = VNRecognizeTextRequest()
if #available(macOS 11.0, *) {
    do {
        let supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: request.revision)
        print("Supported:", supported)
    } catch {
        print("Error")
    }
}
