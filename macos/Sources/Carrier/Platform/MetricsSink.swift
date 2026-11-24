import CarrierCore
import Foundation
import MetricKit

/// The system's reports on how the app ran on this Mac (hangs, CPU and disk exceptions, crashes, and the daily metrics), kept as JSON in
/// `<Carrier folder>/app/logs/metrics/` to attach to a bug report; nothing leaves the Mac. The newest 30 files are kept.
final class MetricsSink: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsSink()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for (index, payload) in payloads.enumerated() { keep(payload.jsonRepresentation(), kind: "metrics", index: index) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for (index, payload) in payloads.enumerated() { keep(payload.jsonRepresentation(), kind: "diagnostics", index: index) }
    }

    private func keep(_ json: Data, kind: String, index: Int) {
        do {
            try keepMetricsReport(json, kind: kind, index: index, in: URL(fileURLWithPath: CarrierPlaces().appMetrics), at: Date())
        } catch {
            FileHandle.standardError.write(Data("carrier: a MetricKit report was not kept: \(error)\n".utf8))
        }
    }
}
