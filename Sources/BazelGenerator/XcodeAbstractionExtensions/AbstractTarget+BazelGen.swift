import FoundationExtension
import PathKit
import XcodeAbstraction

private enum AbstractTargetBazelGenConstants {
    static let frameworkLibSuffix = "_lib"
}

enum BazelGeneratorAbstractTargetError: Error {
    case unimplemented(productType: ProductType)

    var localizedDescription: String {
        switch self {
        case let .unimplemented(productType):
            return "Unimplemented Bazel generation for product type: \(productType)"
        }
    }
}

extension AbstractTarget {
    func buildFilePath(rootPath: Path) -> Path {
        let buildFilePath = path + "BUILD.bazel"
        guard !buildFilePath.isAbsolute else {
            return buildFilePath
        }

        let normalizedBuildFilePath = rootPath + buildFilePath
        return normalizedBuildFilePath
    }
}

extension AbstractTarget {
    func generateBazelFileCreateOperations(rootPath: Path) throws -> [CreateBuildFileOperation] {
        switch productType {
        case .framework:
            return generateFramework(rootPath: rootPath)
        case .application:
            return generatePhoneOSApplication(rootPath: rootPath)
        case .unitTestBundle:
            fallthrough
        case .uiTestBundle:
            fallthrough
        default:
            throw BazelGeneratorAbstractTargetError.unimplemented(productType: productType)
        }
    }
}

private extension AbstractTarget {
    func generateFramework(rootPath: Path) -> [CreateBuildFileOperation] {
        let targetRoot = path.string
        let sourcePaths = sourceFiles.map { sourceFile in
            let fullPath = sourceFile.path.isAbsolute ? sourceFile.path : (rootPath + sourceFile.path)
            return fullPath.string.removePrefix(prefix: targetRoot).removePrefix(prefix: "/")
        }

        let infoPlistDirectory = Path(infoPlistPath.url.deletingLastPathComponent().path)
        let infoPlistBuildFilePath = infoPlistDirectory + "BUILD.bazel"

        let swiftLibraryName = "\(name)\(AbstractTargetBazelGenConstants.frameworkLibSuffix)"

        let infoPlistLabel = "\(name)_InfoPlist"

        let infoPlistLabelFromCurrentTarget = "/" + infoPlistDirectory.string.removePrefix(prefix: rootPath.string) + ":\(infoPlistLabel)"

        return [
            CreateBuildFileOperation(targetPath: buildFilePath(rootPath: rootPath), rules: [
                .swiftLibrary(name: swiftLibraryName, srcs: sourcePaths, deps: dependencyLabels, moduleName: name),
                .iosFramework(name: name, deps: [":\(swiftLibraryName)"], bundleID: "to.do.\(name)", minimumOSVersion: "13.0", deviceFamilies: [.iphone], infoPlists: [infoPlistLabelFromCurrentTarget]),
            ]),
            CreateBuildFileOperation(targetPath: infoPlistBuildFilePath, rules: [
                .filegroup(name: infoPlistLabel, srcs: [
                    infoPlistPath.string.removePrefix(prefix: infoPlistDirectory.string).removePrefix(prefix: "/"), // TODO: better path handling (<https://github.com/XcodeMigrate/XcodeMigrate/issues/6>)
                ]),
            ]),
        ]
    }

    func generatePhoneOSApplication(rootPath: Path) -> [CreateBuildFileOperation] {
        let targetRoot = path.string
        let sourcePaths = sourceFiles.map { sourceFile in
            let fullPath = sourceFile.path.isAbsolute ? sourceFile.path : (rootPath + sourceFile.path)
            return fullPath.string.removePrefix(prefix: targetRoot).removePrefix(prefix: "/")
        }

        let sourceName = "\(name)_source"
        let mainTargetSource: BazelRule = .swiftLibrary(
            name: sourceName,
            srcs: sourcePaths,
            deps: dependencyLabels.map { dependencyLabel in
                dependencyLabel + AbstractTargetBazelGenConstants.frameworkLibSuffix
            },
            moduleName: name
        )

        let infoPlistDirectory = Path(infoPlistPath.url.deletingLastPathComponent().path)
        let infoPlistBuildFilePath = infoPlistDirectory + "BUILD.bazel"

        let infoPlistLabel = "\(name)_InfoPlist"

        let infoPlistLabelFromCurrentTarget = "/" + infoPlistDirectory.string.removePrefix(prefix: rootPath.string) + ":\(infoPlistLabel)"

        let applicationBuildFilePath = path + "BUILD.bazel"

        return [
            CreateBuildFileOperation(targetPath: applicationBuildFilePath, rules: [
                .iosApplication(
                    name: name,
                    deps: [
                        ":\(sourceName)",
                    ] + dependencyLabels,
                    infoplists: [infoPlistLabelFromCurrentTarget],
                    minimumOSVersion: "13.0", // TODO: Parse deployment target (<https://github.com/XcodeMigrate/XcodeMigrate/issues/7>)
                    deviceFamilies: [.iphone] // TODO: Parse device family (<https://github.com/XcodeMigrate/XcodeMigrate/issues/8>)
                ),
                mainTargetSource,
            ]),
            CreateBuildFileOperation(targetPath: infoPlistBuildFilePath, rules: [
                .filegroup(name: infoPlistLabel, srcs: [
                    infoPlistPath.string.removePrefix(prefix: infoPlistDirectory.string).removePrefix(prefix: "/"),
                ]),
            ]),
        ]
    }
}

private extension AbstractTarget {
    var dependencyLabels: [String] {
        return dependencies.map { dependency in
            let commonPathPrefix = String.commonPrefix(strings: [
                self.path.string,
                dependency.path.string,
            ])
            let dependencyLabelWithOutCommonPath = dependency.path.string[commonPathPrefix.endIndex...]
            return "/\(dependencyLabelWithOutCommonPath):\(dependency.name)"
        }
    }
}
