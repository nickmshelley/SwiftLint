//
//  Rule.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-05-16.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import SourceKittenFramework

public protocol Rule {
    init() // Rules need to be able to be initialized with default values
    init(config: AnyObject) throws
    static var description: RuleDescription { get }
    func validateFile(file: File) -> [StyleViolation]
    func isEqualTo(rule: Rule) -> Bool
    var configDescription: String { get }
}

extension Rule {
    public func isEqualTo(rule: Rule) -> Bool {
        return self.dynamicType.description == rule.dynamicType.description
    }
}

public protocol OptInRule: Rule {}

public protocol ConfigProviderRule: Rule {
    typealias ConfigType: RuleConfig
    var config: ConfigType { get set }
}

public protocol CorrectableRule: Rule {
    func correctFile(file: File) -> [Correction]
}

// MARK: - ConfigProviderRule conformance to Configurable

public extension ConfigProviderRule {
    public init(config: AnyObject) throws {
        self.init()
        try self.config.setConfig(config)
    }

    public func isEqualTo(rule: Rule) -> Bool {
        if let rule = rule as? Self {
            return config.isEqualTo(rule.config)
        }
        return false
    }

    public var configDescription: String {
        return config.consoleDescription
    }
}

// MARK: - == Implementations

public func == (lhs: [Rule], rhs: [Rule]) -> Bool {
    if lhs.count == rhs.count {
        return zip(lhs, rhs).map { $0.isEqualTo($1) }.reduce(true) { $0 && $1 }
    }

    return false
}
