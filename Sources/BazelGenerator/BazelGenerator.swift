import Common
import Foundation
import PathKit
import XcodeAbstraction

let logger = Logger(label: "BazelGenerator")

public enum BazelGenerator {}

public extension BazelGenerator {
    static func generate(from project: AbstractProject) throws {
        let fileManager = FileManager.default
        var globalRuleSet: Set<BazelRuleSet> = []
        var buildFileOperations: [Path: [CreateBuildFileOperation]] = [:]

        for target in project.targets {
            guard let createBuildFileOperations = try? target.generateBazelFileCreateOperations(rootPath: project.rootPath) else {
                // TODO: Test all supported product types
                logger.critical("Failed to generate Bazel file for target: \(target.name) because of unsupported product type: \(target.productType)")
                continue
            }
            for operation in createBuildFileOperations {
                for generatedRule in operation.rules {
                    globalRuleSet.insert(generatedRule.ruleSet)
                }

                buildFileOperations[operation.targetPath, default: []].append(operation)
            }
        }

        let workspaceRuleSetStrings = globalRuleSet.map(\.workspaceContent)

        let httpArchive = """
        load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
        """
        let workspaceString = httpArchive + "\n" + workspaceRuleSetStrings.joined(separator: "\n")

        let workspaceFilePath = project.rootPath + "WORKSPACE"

        if fileManager.fileExists(atPath: workspaceFilePath.string) {
            try fileManager.removeItem(at: workspaceFilePath.url)
        }

        fileManager.createFile(atPath: workspaceFilePath.string, contents: workspaceString.data(using: .utf8), attributes: nil)

        try generateBuildFiles(fileManager: fileManager, operationMapping: buildFileOperations)
    }
}

private extension BazelGenerator {
    static func generateBuildFiles(fileManager: FileManager, operationMapping: [Path: [CreateBuildFileOperation]]) throws {
        for (path, operations) in operationMapping {
            let mergedRuleLoadingStatements = CreateBuildFileOperation.aggregatedLoadingStatements(of: operations).joined(separator: "\n")
            let allRules = operations.map(\.allRules).joined(separator: "\n")

            if fileManager.fileExists(atPath: path.string) {
                try fileManager.removeItem(atPath: path.string)
            }

            let fullContent = mergedRuleLoadingStatements + "\n" + allRules

            fileManager.createFile(atPath: path.string, contents: fullContent.data(using: .utf8))
        }
    }
}
