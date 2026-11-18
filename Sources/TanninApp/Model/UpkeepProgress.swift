import TanninCore

/// Where the after-update step stands, for the rows at the top of the Engine page.
enum UpkeepProgress: Equatable {
    case working(Upkeep.Item)
    case finished
    /// Nothing was changed; the text says what went wrong.
    case failed(Upkeep.Item, String)
}
