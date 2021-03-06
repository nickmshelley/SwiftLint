//
//  LintCommand.swift
//  SwiftLint
//
//  Created by JP Simard on 2015-05-16.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import Commandant
import Foundation
import Result
import SourceKittenFramework
import SwiftLintFramework

struct LintCommand: CommandType {
    let verb = "lint"
    let function = "Print lint warnings and errors (default command)"

    func run(options: LintOptions) -> Result<(), CommandantError<()>> {
        var fileTimes = [(id: String, time: Double)]()
        var ruleTimes = [(id: String, time: Double)]()
        var violations = [StyleViolation]()
        let configuration = Configuration(commandLinePath: options.configurationFile,
            rootPath: options.path, quiet: options.quiet)
        let reporter = reporterFromString(
            options.reporter.isEmpty ? configuration.reporter : options.reporter
        )
        return configuration.visitLintableFiles(options.path, action: "Linting",
            useSTDIN: options.useSTDIN, quiet: options.quiet,
            useScriptInputFiles: options.useScriptInputFiles) { linter in
            let start: NSDate! = options.benchmark ? NSDate() : nil
            var currentViolations: [StyleViolation] = []
            autoreleasepool {
                if options.benchmark {
                    let (_currentViolations, currentRuleTimes) = linter.styleViolationsAndRuleTimes
                    currentViolations = _currentViolations
                    fileTimes.append((linter.file.path ?? "<nopath>", -start.timeIntervalSinceNow))
                    ruleTimes.appendContentsOf(currentRuleTimes)
                } else {
                    currentViolations = linter.styleViolations
                }
                linter.file.invalidateCache()
            }
            violations += currentViolations
            if reporter.isRealtime {
                let report = reporter.generateReport(currentViolations)
                if !report.isEmpty {
                    queuedPrint(report)
                }
            }
        }.flatMap { files in
            if !reporter.isRealtime {
                queuedPrint(reporter.generateReport(violations))
            }
            let numberOfSeriousViolations = violations.filter({ $0.severity == .Error }).count
            if !options.quiet {
                LintCommand.printStatus(violations: violations, files: files,
                    serious: numberOfSeriousViolations)
            }
            if options.benchmark {
                saveBenchmark("files", times: fileTimes)
                saveBenchmark("rules", times: ruleTimes)
            }
            if (options.strict && !violations.isEmpty) || numberOfSeriousViolations > 0 {
                return .Failure(CommandantError<()>.CommandError())
            }
            return .Success()
        }
    }

    static func printStatus(violations violations: [StyleViolation], files: [File], serious: Int) {
        let violationSuffix = (violations.count != 1 ? "s" : "")
        let fileCount = files.count
        let filesSuffix = (fileCount != 1 ? "s." : ".")
        let message = "Done linting! Found \(violations.count) violation\(violationSuffix), " +
            "\(serious) serious in \(fileCount) file\(filesSuffix)"
        queuedPrintError(message)
    }
}

struct LintOptions: OptionsType {
    let path: String
    let useSTDIN: Bool
    let configurationFile: String
    let strict: Bool
    let useScriptInputFiles: Bool
    let benchmark: Bool
    let reporter: String
    let quiet: Bool

    // swiftlint:disable line_length
    static func create(path: String) -> (useSTDIN: Bool) -> (configurationFile: String) -> (strict: Bool) -> (useScriptInputFiles: Bool) -> (benchmark: Bool) -> (reporter: String) -> (quiet: Bool) -> LintOptions {
        return { useSTDIN in { configurationFile in { strict in { useScriptInputFiles in { benchmark in { reporter in { quiet in
            self.init(path: path, useSTDIN: useSTDIN, configurationFile: configurationFile, strict: strict, useScriptInputFiles: useScriptInputFiles, benchmark: benchmark, reporter: reporter, quiet: quiet)
        }}}}}}}
    }

    static func evaluate(mode: CommandMode) -> Result<LintOptions, CommandantError<CommandantError<()>>> {
        // swiftlint:enable line_length
        return create
            <*> mode <| Option(key: "path",
                defaultValue: "",
                usage: "the path to the file or directory to lint")
            <*> mode <| Option(key: "use-stdin",
                defaultValue: false,
                usage: "lint standard input")
            <*> mode <| Option(key: "config",
                defaultValue: Configuration.fileName,
                usage: "the path to SwiftLint's configuration file")
            <*> mode <| Option(key: "strict",
                defaultValue: false,
                usage: "fail on warnings")
            <*> mode <| Option(key: "use-script-input-files",
                defaultValue: false,
                usage: "read SCRIPT_INPUT_FILE* environment variables as files")
            <*> mode <| Option(key: "benchmark",
                defaultValue: false,
                usage: "save benchmarks to benchmark_files.txt and benchmark_rules.txt")
            <*> mode <| Option(key: "reporter",
                defaultValue: "",
                usage: "the reporter used to log errors and warnings")
            <*> mode <| Option(key: "quiet",
                defaultValue: false,
                usage: "don't print status logs like 'Linting <file>' & 'Done linting'")
    }
}
