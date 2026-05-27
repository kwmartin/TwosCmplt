import Foundation

/**
 * readMuxData reads the data from a file
 *
 * - Parameter filename: String, the filename of the data. It is expected
 *   the data is in the same directory as this file
 *
 * -Returns: [Int], an array of the data
 */
public func readDat(from filename: String) throws -> [Int] {
    let content = try String(contentsOfFile: filename, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    let hexInts = lines.compactMap { line in
        let hexString = line.hasPrefix("0x") ? String(line.dropFirst(2)) : line
        return Int(hexString, radix: 16)
    }
    return hexInts
}

/**
 * rdData reads the data from a file
 *
 * - Parameter filename: String, the filename of the data. It is expected
 *   the data is in the same directory as the file where rdData is called.
 *   This file sets the path and then calls readDat() to actually handle the
 *   file input and change the ascii to Int's that are returned in an Array.
 *
 * -Returns: [Int], an array of the data
 */
public func rdData(from filename: String) -> [Int] {
    var vals: [Int]?
    do {
        let cwd = FileManager.default.currentDirectoryPath
        let path = "\(cwd)/Examples/Resources/\(filename)"
        vals = try readDat(from: path)
        // print(vals ?? [])
    } catch {
        print("Failed to read or parse file: \(error)")
    }
    return vals ?? []
}
