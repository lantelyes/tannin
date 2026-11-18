/// How adding D3DMetal from a disk image is going, for the sheet that asks for it.
enum D3DMetalAdd: Equatable {
    case idle
    /// Tannin is checking the disk image with this name.
    case checking(String)
    /// The last one was not added; the sentence says why.
    case failed(String)
}
