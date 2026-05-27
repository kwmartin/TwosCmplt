import Foundation
import Yams
import Configuration

public struct ProjectConfig: Codable {
    public struct Project: Codable {
        public let name: String
        public let buildDir: String
        public let docsDir: String
    }

    public struct Paths: Codable {
        public let sources: String
        public let scripts: String
    }

    public struct Directories: Codable {
        public let dumpDir: String
        public let vcdDir: String
        public let modDir: String
        public let circLib: String
    }

    public struct FileNames: Codable {
        public let nodeChngs: String
        public let python: String
        public let vcdScript: String
    }

    public struct Technology: Codable {
        public let inv4delay: Int
        public let cap2ps: Double
    }

    public let project: Project
    public let paths: Paths
    public let directories: Directories
    public let fileNames: FileNames
    public let technology: Technology
}

enum ConfigLoader {
    static func load(from path: String = "Config.yaml") throws -> ProjectConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ConfigLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"])
        }
        return try YAMLDecoder().decode(ProjectConfig.self, from: yamlString)
    }
}
