import Foundation

extension Int64 {
    /// "461 MB": a download's size in whole megabytes, which is as exact as anyone watching one needs.
    var megabytes: String {
        "\(Int((Double(self) / 1_000_000).rounded())) MB"
    }
}
