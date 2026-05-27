// Glbls.swift
import SharedTypes

/*
@globalActor
public actor StatesActor {
    public static let shared = StatesActor()
}
*/

// @StatesActor
public final class States {
    // Enumerations for mode types
    public enum MultiplyModes { case truncate, full }
    public enum AddModes { case overflow, saturate }

    // Actor-isolated global states
    nonisolated(unsafe) public static var multiplyMode: MultiplyModes = .full
    nonisolated(unsafe) public static var addMode: AddModes = .overflow

    // Singleton-like shared instance
    // public static let shared = States()

    // Convenience initializer
    // public init() {}
}

public enum Glbls {
    nonisolated(unsafe) public static var mltTruncate: Bool = false
    nonisolated(unsafe) public static var a3_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a2_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a1_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a0_: [TwoCmplt] = []
    nonisolated(unsafe) public static var arry: [TwoCmplt] = []
}