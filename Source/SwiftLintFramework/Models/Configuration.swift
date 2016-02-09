//
//  Configuration.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-08-23.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import Foundation
import SourceKittenFramework

private let fileManager = NSFileManager.defaultManager()

private enum ConfigurationKey: String {
    case DisabledRules = "disabled_rules"
    case EnabledRules = "enabled_rules" // deprecated in favor of OptInRules
    case Excluded = "excluded"
    case Included = "included"
    case OptInRules = "opt_in_rules"
    case Reporter = "reporter"
    case UseNestedConfigs = "use_nested_configs"
    case WhitelistRules = "whitelist_rules"
}

public struct Configuration: Equatable {
    public static let fileName = ".swiftlint.yml"
    public let included: [String]      // included
    public let excluded: [String]      // excluded
    public let reporter: String        // reporter (xcode, json, csv, checkstyle)
    public let rules: [Rule]
    public let useNestedConfigs: Bool  // process nested configs, will default to false
    public var rootPath: String?       // the root path of the lint to search for nested configs
    public var configPath: String?     // if successfully loaded from a path

    public init?(disabledRules: [String] = [],
                 optInRules: [String] = [],
                 whitelistRules: [String] = [],
                 included: [String] = [],
                 excluded: [String] = [],
                 reporter: String = XcodeReporter.identifier,
                 configuredRules: [Rule] = masterRuleList.configuredRulesWithDictionary([:]),
                 useNestedConfigs: Bool = false) {
        self.included = included
        self.excluded = excluded
        self.reporter = reporter
        self.useNestedConfigs = useNestedConfigs

        // Validate that all rule identifiers map to a defined rule
        let validRuleIdentifiers = configuredRules.map {
            $0.dynamicType.description.identifier
        }

        let validDisabledRules = disabledRules.filter({ validRuleIdentifiers.contains($0)})
        let invalidRules = disabledRules.filter({ !validRuleIdentifiers.contains($0) })
        if !invalidRules.isEmpty {
            for invalidRule in invalidRules {
                queuedPrintError("config error: '\(invalidRule)' is not a valid rule identifier")
            }
            let listOfValidRuleIdentifiers = validRuleIdentifiers.joinWithSeparator("\n")
            queuedPrintError("Valid rule identifiers:\n\(listOfValidRuleIdentifiers)")
        }

        // Validate that rule identifiers aren't listed multiple times
        if Set(validDisabledRules).count != validDisabledRules.count {
            let duplicateRules = validDisabledRules.reduce([String: Int]()) { accu, element in
                var accu = accu
                accu[element] = accu[element]?.successor() ?? 1
                return accu
            }.filter { $0.1 > 1 }
            queuedPrintError(duplicateRules.map { rule in
                "config error: '\(rule.0)' is listed \(rule.1) times"
            }.joinWithSeparator("\n"))
            return nil
        }

        // white_list rules take precendence over all else.
        if !whitelistRules.isEmpty {
            if !disabledRules.isEmpty || !optInRules.isEmpty {
                queuedPrintError("'\(ConfigurationKey.DisabledRules.rawValue)' or " +
                    "'\(ConfigurationKey.OptInRules.rawValue)' cannot be used in combination " +
                    "with '\(ConfigurationKey.WhitelistRules.rawValue)'")
                return nil
            }

            rules = configuredRules.filter { rule in
                return whitelistRules.contains(rule.dynamicType.description.identifier)
            }
        } else {
            rules = configuredRules.filter { rule in
                let id = rule.dynamicType.description.identifier
                if validDisabledRules.contains(id) { return false }
                return optInRules.contains(id) || !(rule is OptInRule)
            }
        }
    }

    public init?(dict: [String: AnyObject]) {
        // Deprecation warning for "enabled_rules"
        if dict[ConfigurationKey.EnabledRules.rawValue] != nil {
            queuedPrintError("'\(ConfigurationKey.EnabledRules.rawValue)' has been renamed to " +
                "'\(ConfigurationKey.OptInRules.rawValue)' and will be completely removed in a " +
                "future release.")
        }

        func defaultStringArray(object: AnyObject?) -> [String] {
            return [String].arrayOf(object) ?? []
        }

        // Use either new 'opt_in_rules' or deprecated 'enabled_rules' for now.
        let optInRules = defaultStringArray(
            dict[ConfigurationKey.OptInRules.rawValue] ??
                dict[ConfigurationKey.EnabledRules.rawValue]
        )

        // Log an error when supplying invalid keys in the configuration dictionary
        let validKeys = [
            ConfigurationKey.DisabledRules,
            .EnabledRules,
            .Excluded,
            .Included,
            .OptInRules,
            .Reporter,
            .UseNestedConfigs,
            .WhitelistRules,
        ].map({ $0.rawValue }) + masterRuleList.list.keys

        let invalidKeys = Set(dict.keys).subtract(validKeys)
        if !invalidKeys.isEmpty {
            queuedPrintError("Configuration contains invalid keys:\n\(invalidKeys)")
        }

        self.init(
            disabledRules: defaultStringArray(dict[ConfigurationKey.DisabledRules.rawValue]),
            optInRules: optInRules,
            whitelistRules: defaultStringArray(dict[ConfigurationKey.WhitelistRules.rawValue]),
            included: defaultStringArray(dict[ConfigurationKey.Included.rawValue]),
            excluded: defaultStringArray(dict[ConfigurationKey.Excluded.rawValue]),
            reporter: dict[ConfigurationKey.Reporter.rawValue] as? String ??
                XcodeReporter.identifier,
            useNestedConfigs: dict[ConfigurationKey.UseNestedConfigs.rawValue] as? Bool ?? false,
            configuredRules: masterRuleList.configuredRulesWithDictionary(dict)
        )
    }

    public init(path: String = Configuration.fileName, rootPath: String? = nil,
                optional: Bool = true, quiet: Bool = false) {
        let fullPath = (path as NSString).absolutePathRepresentation()
        let fail = { fatalError("Could not read configuration file at path '\(fullPath)'") }
        if path.isEmpty || !NSFileManager.defaultManager().fileExistsAtPath(fullPath) {
            if !optional { fail() }
            self.init()!
            return
        }
        do {
            let yamlContents = try NSString(contentsOfFile: fullPath,
                encoding: NSUTF8StringEncoding) as String
            let dict = try YamlParser.parse(yamlContents)
            if !quiet {
                queuedPrintError("Loading configuration from '\(path)'")
            }
            self.init(dict: dict)!
            configPath = fullPath
            return
        } catch {
            fail()
        }
        self.init()!
    }

    public func lintablePathsForPath(path: String,
                                     fileManager: NSFileManager = fileManager) -> [String] {
        let pathsForPath = included.isEmpty ? fileManager.filesToLintAtPath(path) : []
        let excludedPaths = excluded.flatMap(fileManager.filesToLintAtPath)
        let includedPaths = included.flatMap(fileManager.filesToLintAtPath)
        return (pathsForPath + includedPaths).filter({ !excludedPaths.contains($0) })
    }

    public func lintableFilesForPath(path: String) -> [File] {
        return lintablePathsForPath(path).flatMap { File(path: $0) }
    }

    public func configForFile(file: File) -> Configuration {
        if useNestedConfigs,
            let containingDir = (file.path as NSString?)?.stringByDeletingLastPathComponent {
            return configForPath(containingDir)
        }
        return self
    }
}

// MARK: - Nested Configurations Extension

extension Configuration {
    private func configForPath(path: String) -> Configuration {
        let path = path as NSString
        let configSearchPath = path.stringByAppendingPathComponent(Configuration.fileName)

        // If a config exists and it isn't us, load and merge the configs
        if configSearchPath != configPath &&
            NSFileManager.defaultManager().fileExistsAtPath(configSearchPath) {
            return merge(Configuration(path: configSearchPath, optional: false, quiet: true))
        }

        // If we are not at the root path, continue down the tree
        if path != rootPath && path != "/" {
            return configForPath(path.stringByDeletingLastPathComponent)
        }

        // If nothing else, return self
        return self
    }

    // Currently merge simply overrides the current configuration with the new configuration.
    // This requires that all config files be fully specified. In the future this will be changed
    // to do a more intelligent merge allowing for partial nested configs.
    internal func merge(config: Configuration) -> Configuration {
        return config
    }
}

// Mark - == Implementation

public func == (lhs: Configuration, rhs: Configuration) -> Bool {
    return (lhs.excluded == rhs.excluded) &&
           (lhs.included == rhs.included) &&
           (lhs.reporter == rhs.reporter) &&
           (lhs.useNestedConfigs == rhs.useNestedConfigs) &&
           (lhs.configPath == rhs.configPath) &&
           (lhs.rootPath == lhs.rootPath) &&
           (lhs.rules == rhs.rules)
}
