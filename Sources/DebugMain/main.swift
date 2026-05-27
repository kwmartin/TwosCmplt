import Testing
import SharedTypes
import TwosCmplt

@testable import TwosCmplt

@Test
func testInit() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let tc = TwoCmplt(value: 123)
    print("Line 8 in main.swift in DebugMain")
    #expect(tc.value == 123)
}
