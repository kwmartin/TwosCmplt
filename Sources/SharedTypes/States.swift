public final class States {
    // Enumerations for mode types
    public enum MultiplyModes { case truncate, full }
    public enum AddModes { case overflow, saturate }
    public enum PrecModes { case none, oneNbl, twoNbl }
    public enum RoundModes { case round, trunc }

    nonisolated(unsafe) public static var multiplyMode: MultiplyModes = .full
    nonisolated(unsafe) public static var addMode: AddModes = .overflow
    nonisolated(unsafe) public static var precMode: PrecModes = .none
    nonisolated(unsafe) public static var roundMode: RoundModes = .round
}
