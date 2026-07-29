import Foundation
import Glibc
import Yams

import SharedTypes

/*
struct MyConfigurable: Sendable {
    let nbits: Int
    let type: String
    // other config fields

    // static cache: key = (nbits, type)
    private static var cache: [Key: MyConfigurable] = [:]

    private struct Key: Hashable {
        let nbits: Int
        let type: String
    }

    init(nbits: Int, type: String) {
        let key = Key(nbits: nbits, type: type)

        if let cached = Self.cache[key] {
            // reuse cached config
            self = cached
            return
        }

        // cold path: read YAML, build config
        let loaded = MyConfigurable.loadFromYAML(nbits: nbits, type: type)

        // store in cache
        Self.cache[key] = loaded

        self = loaded
    }

    private static func loadFromYAML(nbits: Int, type: String) -> MyConfigurable {
        // open YAML, parse, construct MyConfigurable
        // using nbits and type to choose the right section
        fatalError("Implement YAML loading here")
    }
}
*/

struct GateConfig: Sendable {
    // Example: [("and", 2)] -> packedInt
    private let tables: [Key: Tbl]

    struct Key: Hashable, Sendable {
        let kind: Kind
        let ninps: Int
    }

    func table(for kind: Kind, ninps: Int) -> Tbl {
        guard let t = tables[Key(kind: kind, ninps: ninps)] else {
            fatalError("No truth table for \(kind) with \(ninps) inputs")
        }
        return t
    }

    static func loadFromYAML() -> [Key: Tbl] {
        var loadTbl: [Key: Tbl] = [:]
        var yamlString: String = ""
        let dir = URL(fileURLWithPath: "/home/Dropbox/programming/Swift/TwosCmplt/Resources/LogicLib/")

        let gateFiles: [URL]
        do {
            gateFiles = try fileNames(in: dir)
        } catch {
            fatalError("Failed to list gate files: \(error)")
        }

        for fileNm in gateFiles {
            // Skip tech file as before
            if fileNm.lastPathComponent == "tech_20.yml" {
                continue
            }

            do {
                yamlString = try String(contentsOfFile: fileNm.path, encoding: .utf8)
                //Swift.print("yamlString: \(yamlString)")
            } catch {
                print("Could not read YAML file at \(fileNm): \(error)")
                continue
            }

            do {
                guard let parsed = try Yams.load(yaml: yamlString) as? [String: Any],
                    let kindStr = parsed["kind"] as? String,
                    let ninps = parsed["ninps"] as? Int
                else {
                    print("YAML missing required fields or invalid types in \(fileNm)")
                    continue
                }

                guard let kind = Kind(rawValue: kindStr) else {
                    print("Unknown gate kind '\(kindStr)' in \(fileNm)")
                    continue
                }

                var table: Tbl? = nil
                if let tableInt = parsed["table"] as? Int {
                    table = .tbl(int: tableInt)
                } else if let tableInts = parsed["table"] as? [Int] {
                    table = .tbls(ints: tableInts)
                } else {
                    // No table provided: this is allowed for certain kinds, like .join
                    if kind == .join {
                        // OK: join will be evaluated algorithmically
                        Swift.print("No table for join gate in \(fileNm), using algorithmic eval")
                    } else if kind == .custom {
                        // custom: we may still want the table, but if missing, that's an error
                        print("Custom gate without table in \(fileNm) — ignoring")
                        continue
                    } else {
                        print("YAML missing 'table' for kind \(kind) in \(fileNm)")
                        continue
                    }
                }

                if kindStr == "custom" {
                    let customNm = fileNm.deletingPathExtension().lastPathComponent
                    if let tbl = table {
                        Glbls.cstmGt[customNm] = tbl
                        print("Glbls.cstmGt[customNm]: \(Glbls.cstmGt[customNm]!)")
                    } else {
                        print("Custom gate \(customNm) has no table; skipping")
                    }
                }

                // print("kind: \(kindStr)")
                // print("ninps: \(ninps)")
                // if let t = table { print("table: \(t)") }

                if let t = table {
                    let key = Key(kind: kind, ninps: ninps)
                    loadTbl[key] = t
                    // print("loaded[key]: \(String(describing: loadTbl[key]))")
                }

            } catch {
                print("Failed to parse YAML \(fileNm): \(error)")
            }

            // print(fileNm.path)
        }

        let table = loadTbl
        // print("In loadFromYaml(), returning tables with \(table.count) elements")
        return table
    }
}
