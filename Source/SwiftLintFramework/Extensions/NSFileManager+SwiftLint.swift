//
//  NSFileManager+SwiftLint.swift
//  SwiftLint
//
//  Created by JP Simard on 5/28/15.
//  Copyright (c) 2015 Realm. All rights reserved.
//

import Foundation

extension NSFileManager {
    internal func filesToLintAtPath(path: String) -> [String] {
        let absolutePath = path.absolutePathStandardized()
        var isDirectory: ObjCBool = false
        guard fileExistsAtPath(absolutePath, isDirectory: &isDirectory) else {
            return []
        }
        if isDirectory {
            do {
                return try subpathsOfDirectoryAtPath(absolutePath)
                    .map((absolutePath as NSString).stringByAppendingPathComponent).filter {
                        $0.isSwiftFile()
                }
            } catch {
                fatalError("Couldn't find files in \(absolutePath): \(error)")
            }
        } else if absolutePath.isSwiftFile() {
            return [absolutePath]
        }
        return []
    }
}
