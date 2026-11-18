import Foundation

extension Int64 {
    /// "461 MB": a download's size in whole megabytes, which is as exact as anyone watching one needs.
    var megabytes: String {
        "\(Int((Double(self) / 1_000_000).rounded())) MB"
    }

    /// "650 MB": a total rounded to the nearest ten, for a sentence that says "about".
    var roundedMegabytes: String {
        "\(Int((Double(self) / 10_000_000).rounded()) * 10) MB"
    }
}
