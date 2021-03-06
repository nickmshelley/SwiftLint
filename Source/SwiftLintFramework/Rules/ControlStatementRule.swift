//
//  ControlStatementRule.swift
//  SwiftLint
//
//  Created by Andrea Mazzini on 26/05/15.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import SourceKittenFramework

public struct ControlStatementRule: ConfigProviderRule {

    public var config = SeverityConfig(.Warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "control_statement",
        name: "Control Statement",
        description: "if,for,while,do statements shouldn't wrap their conditionals in parentheses.",
        nonTriggeringExamples: [
            "if condition {\n",
            "if (a, b) == (0, 1) {\n",
            "if (a || b) && (c || d) {\n",
            "if (min...max).contains(value) {\n",
            "if renderGif(data) {\n",
            "renderGif(data)\n",
            "for item in collection {\n",
            "for (key, value) in dictionary {\n",
            "for (index, value) in enumerate(array) {\n",
            "for var index = 0; index < 42; index++ {\n",
            "guard condition else {\n",
            "while condition {\n",
            "} while condition {\n",
            "do { ; } while condition {\n",
            "switch foo {\n"
        ],
        triggeringExamples: [
            "↓if (condition) {\n",
            "↓if(condition) {\n",
            "↓if ((a || b) && (c || d)) {\n",
            "↓if ((min...max).contains(value)) {\n",
            "↓for (item in collection) {\n",
            "↓for (var index = 0; index < 42; index++) {\n",
            "↓for(item in collection) {\n",
            "↓for(var index = 0; index < 42; index++) {\n",
            "↓guard (condition) else {\n",
            "↓while (condition) {\n",
            "↓while(condition) {\n",
            "} ↓while (condition) {\n",
            "} ↓while(condition) {\n",
            "do { ; } ↓while(condition) {\n",
            "do { ; } ↓while (condition) {\n",
            "↓switch (foo) {\n"
        ]
    )

    public func validateFile(file: File) -> [StyleViolation] {
        let statements = ["if", "for", "guard", "switch", "while"]
        return statements.flatMap { statementKind -> [StyleViolation] in
            let pattern = statementKind == "guard"
                ? "\(statementKind)\\s*\\([^,{]*\\)\\s*else\\s*\\{"
                : "\(statementKind)\\s*\\([^,{]*\\)\\s*\\{"
            return file.matchPattern(pattern).flatMap { match, syntaxKinds in
                let matchString = file.contents.substring(match.location, length: match.length)
                if self.isFalsePositive(matchString, syntaxKind: syntaxKinds.first) {
                    return nil
                }
                return StyleViolation(ruleDescription: self.dynamicType.description,
                    severity: self.config.severity,
                    location: Location(file: file, characterOffset: match.location))
            }
        }

    }

    private func isFalsePositive(content: String, syntaxKind: SyntaxKind?) -> Bool {
        if syntaxKind != .Keyword {
            return true
        }

        guard let lastClosingParenthesePosition = content.lastIndexOf(")") else {
            return false
        }

        var depth = 0
        var index = 0
        for char in content.characters {
            if char == ")" {
                if index != lastClosingParenthesePosition && depth == 1 {
                    return true
                }
                depth -= 1
            } else if char == "(" {
                depth += 1
            }
            index += 1
        }
        return false
    }
}
