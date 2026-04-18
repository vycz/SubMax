import Foundation
import Testing
@testable import SubMaxCore

@Test func defaultProbeProfileUsesClientLikeLatencyAndLargerDownloadSample() {
    let profile = ProbeProfile()

    #expect(profile.latencyURL.absoluteString == "http://www.gstatic.com/generate_204")
    #expect(profile.timeoutSeconds == 20)
    #expect(profile.latencySampleCount == 5)
    #expect(profile.downloadDurationSeconds == 8)
    #expect(profile.downloadNoDataTimeoutSeconds == 5)
    #expect(profile.downloadLimitBytes == 50_000_000)
    #expect(profile.downloadURL.absoluteString.contains("bytes=50000000"))
}
