//
//  XcodeHelperCli.swift
//  XcodeHelper
//
//  Created by Joel Saltzman on 8/28/16.
//
//

import Foundation
import XcodeHelperKit
import CliRunnable

public enum XcodeHelperCliError : Error, CustomStringConvertible {
    case xcactivityLogDecode(message:String)
    public var description : String {
        get {
            switch (self) {
            case let .xcactivityLogDecode(message): return message
            }
        }
    }
}

public struct XCHelper : CliRunnable {
    
    public var xcodeHelpable: XcodeHelpable
    
    public init(xcodeHelpable:XcodeHelpable = XcodeHelper()) {
        self.xcodeHelpable = xcodeHelpable
    }
    
    public var appName: String {
        get {
            return "xchelper"
        }
    }
    public var description: String? {
        get {
            return "xchelper keeps in Xcode and off the command line. You can build and run tests on Linux through Docker, fetch Swift packages, keep your \"Dependencies\" group in Xcode referencing the correct paths and tar and upload you Linux binary to AWS S3 buckets."
        }
    }
    public var appUsage: String? {
        return "xchelper COMMAND [OPTIONS]"
    }
    
    public func parseSourceCodePath(from argumentIndex: [String:[String]], with optionKey: String?) -> String {
        if let key = optionKey, let customDirectory = argumentIndex[key]?.first {
            return customDirectory
        }
        return FileManager.default.currentDirectoryPath
    }
    
    
    public var cliOptionGroups: [CliOptionGroup] {
        get {
            return [CliOptionGroup(description:"Commands:",
                                   options:[updateMacOsPackagesOption, updateDockerPackagesOption, dockerBuildOption, cleanOption, symlinkDependenciesOption, createArchiveOption, uploadArchiveOption, gitTagOption, createXcarchiveOption])]
        }
    }
    public var environmentKeys: [String] {
        return cliOptionGroups.flatMap{ (optionGroup: CliOptionGroup) in
            return optionGroup.options.flatMap{ (option: CliOption) in
                return option.allKeys.filter{ (key: String) -> Bool in
                    return key.uppercased() == key
                }
            }
        }
    }
    
    // MARK: UpdatePackages
    struct updateMacOsPackages {
        static let command          = CliOption(keys: ["update-macos-packages", "UPDATE_MACOS_PACKAGES"],
                                                description: "Update the package dependencies via 'swift package update' without breaking your file references in Xcode.",
                                                usage: "xchelper update-packages [OPTIONS]",
                                                requiresValue: false,
                                                defaultValue:nil)
        static let changeDirectory  = CliOption(keys:["-d", "--chdir", "UPDATE_MACOS_PACKAGES_CHDIR"],
                                                description:"Change the current working directory.",
                                                usage:nil,
                                                requiresValue:true,
                                                defaultValue:nil)
        static let generateXcodeProject  = CliOption(keys:["-g", "--generate", "UPDATE_PACKAGES_GENERATE_XCPROJECT"],
                                                description:"Generate a new Xcode project",
                                                usage: nil,
                                                requiresValue:false,
                                                defaultValue: nil)
        static let symlink          = CliOption(keys:["-s", "--symlink", "UPDATE_PACKAGES_SYMLINK"],
                                                description:"Create symbolic links for the dependency 'Packages' after `swift package update` so you don't have to generate a new xcode project.",
                                                usage: nil,
                                                requiresValue:false,
                                                defaultValue: nil)
    }
    public var updateMacOsPackagesOption: CliOption {
        var updateMacOsPackagesOption = updateMacOsPackages.command
        updateMacOsPackagesOption.optionalArguments = [updateMacOsPackages.changeDirectory, updateMacOsPackages.generateXcodeProject, updateMacOsPackages.symlink]
        updateMacOsPackagesOption.action = handleUpdatePackages
        return updateMacOsPackagesOption
    }
    public func handleUpdatePackages(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: updateMacOsPackages.changeDirectory.keys.first)
        try xcodeHelpable.updateMacOsPackages(at: sourcePath)
        
        if argumentIndex[updateMacOsPackages.generateXcodeProject.keys.first!] != nil {
            try xcodeHelpable.generateXcodeProject(at: sourcePath)
        }
        if argumentIndex[updateMacOsPackages.symlink.keys.first!] != nil {
            try xcodeHelpable.symlinkDependencies(at: sourcePath)
        }
    }
    
    struct updateDockerPackages {
        static let command          = CliOption(keys: ["update-docker-packages", "UPDATE_DOCKER_PACKAGES"],
                                                description: "Update the packages for your Docker contain in the persistent volume directory",
                                                usage: "xchelper update-docker-packages [OPTIONS]",
                                                requiresValue: false,
                                                defaultValue:nil)
        static let changeDirectory  = CliOption(keys:["-d", "--chdir", "UPDATE_DOCKER_PACKAGES_CHDIR"],
                                                description:"Change the current working directory.",
                                                usage:nil,
                                                requiresValue:true,
                                                defaultValue:nil)
        static let imageName        = CliOption(keys:["-i", "--image-name", "UPDATE_DOCKER_PACKAGES_IMAGE_NAME"],
                                                description:"The Docker image name to run the commands in",
                                                usage: nil,
                                                requiresValue:true,
                                                defaultValue:"saltzmanjoelh/swiftubuntu")
        // The combination of `swift package update` and persistentVolume caused "segmentation fault" and swift compiler crashes
        // For now, when we update packages in Docker we should delete all existing packages first. ie: don't persist Packges directory
        static let volumeName       = CliOption(keys:["-v", "--volume", "UPDATE_DOCKER_PACKAGES_PERSISTENT_VOLUME"],
                                                description:"For now when updating Docker packages, the macOS packages will be renamed, Docker packages update and macOS packages restored.",
                                                usage: nil,
                                                requiresValue:true,
                                                defaultValue: "Docker")
    }
    public var updateDockerPackagesOption: CliOption {
        var updateOption = updateDockerPackages.command
        updateOption.requiredArguments = [updateDockerPackages.imageName]
        updateOption.optionalArguments = [updateDockerPackages.changeDirectory]
        updateOption.action = handleUpdateDockerPackages
        return updateOption
    }
    public func handleUpdateDockerPackages(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: updateMacOsPackages.changeDirectory.keys.first)
        guard let imageName = argumentIndex[updateDockerPackages.imageName.keys.first!]?.first else {
            throw XcodeHelperError.updatePackages(message: "You must provide an image name when updating Docker packages")
        }
        guard let volumeName = argumentIndex[updateDockerPackages.volumeName.keys.first!]?.first else {
            throw XcodeHelperError.updatePackages(message: "You must provide an persistent volume name when updating Docker packages")
        }
        try xcodeHelpable.updateDockerPackages(at: sourcePath, in: imageName, with: volumeName)
    }
    
    // MARK: DockerBuild
    struct dockerBuild {
        static let command              = CliOption(keys: ["docker-build", "DOCKER_BUILD"],
                                                    description: "Build a Swift package in Linux and have the build errors appear in Xcode.",
                                                    usage: "xchelper build [OPTIONS]",
                                                    requiresValue: false,
                                                    defaultValue: nil)
        static let buildOnSuccess       = CliOption(keys: ["-s", "--after-success", "DOCKER_BUILD_AFTER_SUCCESS"],
                                                    description: "Only build after a successful macOS build. This helps reduce duplicate errors in Xcode from multiple platforms.",
                                                    usage: nil,
                                                    requiresValue: false,
                                                    defaultValue: ProcessInfo.processInfo.environment["BUILD_DIR"])
        static let changeDirectory      = CliOption(keys:["-d", "--chdir", "DOCKER_BUILD_CHDIR"],
                                                    description:"Change the current working directory.",
                                                    usage: nil,
                                                    requiresValue: true,
                                                    defaultValue: nil)
        static let buildConfiguration   = CliOption(keys:["-c", "--build-configuration", "DOCKER_BUILD_CONFIGURATION"],
                                                    description:"debug or release mode",
                                                    usage: nil,
                                                    requiresValue: true,
                                                    defaultValue:"debug")
        static let imageName            = CliOption(keys:["-i", "--image-name", "DOCKER_BUILD_IMAGE_NAME"],
                                                    description:"The Docker image name to run the commands in",
                                                    usage: nil,
                                                    requiresValue: true,
                                                    defaultValue:"saltzmanjoelh/swiftubuntu")
        
        //TODO: make sure all volumeName options have the same keys
        static let volumeName  = CliOption(keys:["-v", "--persistent-volume", "DOCKER_BUILD_PERSISTENT_VOLUME"],
                                                    description:"Create a subdirectory in the .build directory. This separates the macOS build files from docker build files to make builds faster for each platform.",
                                                    usage: "-v [PLATFORM_NAME] ie: -v android",
                                                    requiresValue: true,
                                                    defaultValue: nil)
        
    }
    public var dockerBuildOption: CliOption {
        var dockerBuildOption = dockerBuild.command
        dockerBuildOption.optionalArguments = [dockerBuild.changeDirectory, dockerBuild.buildConfiguration, dockerBuild.imageName, dockerBuild.volumeName]
        dockerBuildOption.action = handleDockerBuild
        return dockerBuildOption
    }
    public func handleDockerBuild(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: dockerBuild.changeDirectory.keys.first)
        
        guard let buildConfigurationString = argumentIndex[dockerBuild.buildConfiguration.keys.first!]?.first else {
            throw XcodeHelperError.dockerBuild(message: "\(dockerBuild.buildConfiguration.keys) not provided.", exitCode: 1)
        }
        let buildConfiguration = BuildConfiguration(from:buildConfigurationString)
        guard let imageName = argumentIndex[dockerBuild.imageName.keys.first!]?.first else {
            throw XcodeHelperError.dockerBuild(message: "\(dockerBuild.imageName.keys) not provided.", exitCode: 1)
        }
        let persistentVolume = argumentIndex[dockerBuild.volumeName.keys.first!]?.first
        
        if let buildDirectory = argumentIndex[dockerBuild.buildOnSuccess.keys.first!]?.first {
            if let buildURL = xcodeBuildLogDirectory(from: buildDirectory), try !lastBuildWasSuccess(at: buildURL) {
                return
            }
        }
        
        try xcodeHelpable.dockerBuild(sourcePath, with: [.removeWhenDone], using: buildConfiguration, in: imageName, persistentVolumeName: persistentVolume)
    }
    //we have the func here instead of XcodeHelperKit because it requires use of ProcessInfo which is more likely to be available here
    //check BUILD_DIR/../../Logs/Build `ls -t` first item, it's gziped archive, last word in file is success or failed
    //if ls -t becomes a problem, Logs/Build/Cache.db is plist with most recent build in it with a highLevelStatus S or E, most recent build at top
    func lastBuildWasSuccess(at xcodeBuildLogDirectory: URL) throws -> Bool {
        guard let logURL = URLOfLastBuildLog(at: xcodeBuildLogDirectory) else {
            return false //no build log
        }
        let endOfFile = try decode(xcactivityLog: logURL)
        return endOfFile == "succeeded"
    }
    func xcodeBuildLogDirectory(from xcodeBuildDir: String) -> URL? {
        let buildDirURL = URL(fileURLWithPath: xcodeBuildDir)// /target/Build/Products/../../Logs/Build
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
        return buildDirURL
    }
    func URLOfLastBuildLog(at xcodeBuildDirURL: URL) -> URL? {
        //get a list of the files sorted DESC
        let result = Process.run("/bin/ls", arguments: ["-t1", xcodeBuildDirURL.path], printOutput: false, outputPrefix: nil)
        //filter xcactivitylogs and get the first one
        guard let log = result.output?.components(separatedBy: "\n").flatMap({ $0.hasSuffix(".xcactivitylog") ? $0 : nil }).first else {
            return nil
        }
        return xcodeBuildDirURL.appendingPathComponent(log)
    }
    func decode(xcactivityLog: URL) throws -> String? {
        let result = Process.run("/usr/bin/gunzip", arguments: ["-cd", xcactivityLog.path], printOutput: false, outputPrefix: nil)
        guard let output = result.output else {
            throw XcodeHelperCliError.xcactivityLogDecode(message: result.error!)
        }
        let start = output.index(output.endIndex, offsetBy: -9) // succeeded
        let range = start ..< output.endIndex
        return output[range]
        
    }
    
    
    
    // MARK: Clean
    struct clean {
        static let command              = CliOption(keys: ["clean", "CLEAN"],
                                                    description: "Run swift build --clean on your package.",
                                                    usage: "xchelper clean [OPTIONS]",
                                                    requiresValue: false,
                                                    defaultValue:nil)
        static let changeDirectory  = CliOption(keys:["-d", "--chdir", "CLEAN_CHDIR"],
                                                description:"Change the current working directory.",
                                                usage:nil,
                                                requiresValue:true,
                                                defaultValue:nil)
    }
    public var cleanOption: CliOption {
        var cleanOption = clean.command
        cleanOption.optionalArguments = [clean.changeDirectory]
        cleanOption.action = handleClean
        return cleanOption
    }
    public func handleClean(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: clean.changeDirectory.keys.first)
        try xcodeHelpable.clean(sourcePath: sourcePath)
    }
    
    
    // MARK: SymlinkDependencies
    struct symlinkDependencies {
        static let command              = CliOption(keys: ["symlink-dependencies", "SYMLINK_DEPENDENCIES"],
                                                    description: "Create symbolic links for the dependency 'Packages' after `swift package update` so you don't have to generate a new xcode project.",
                                                    usage: "xchelper symlink-dependencies [OPTIONS]",
                                                    requiresValue: false,
                                                    defaultValue:nil)
        static let changeDirectory  = CliOption(keys:["-d", "--chdir", "SYMLINK_DEPENDENCIES_CHDIR"],
                                                description:"Change the current working directory.",
                                                usage:nil,
                                                requiresValue:true,
                                                defaultValue:nil)
    }
    public var symlinkDependenciesOption: CliOption {
        var symlinkDependenciesOption = symlinkDependencies.command
        symlinkDependenciesOption.optionalArguments = [symlinkDependencies.changeDirectory];
        symlinkDependenciesOption.action = handleSymlinkDependencies
        return symlinkDependenciesOption
    }
    public func handleSymlinkDependencies(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: symlinkDependencies.changeDirectory.keys.first)
        try xcodeHelpable.symlinkDependencies(at: sourcePath)
    }
    
    
    // MARK: CreateArchive
    struct createArchive {
        static let command              = CliOption(keys: ["create-archive", "CREATE_ARCHIVE"],
                                                    description: "Archive files with tar.",
                                                    usage: "xchelper create-archive ARCHIVE_PATH FILES [OPTIONS]. ARCHIVE_PATH the full path and filename for the archive to be created. FILES is a space separated list of full paths to the files you want to archive.",
                                                    requiresValue: false,
                                                    defaultValue: nil)
        static let flatList   = CliOption(keys:["-f", "--flat-list", "CREATE_ARCHIVE_FLAT_LIST"],
                                          description:"Put all the files in a flat list instead of maintaining directory structure",
                                          usage: nil,
                                          requiresValue:false,
                                          defaultValue:nil)
    }
    public var createArchiveOption: CliOption {
        var createArchiveOption = createArchive.command
        createArchiveOption.optionalArguments = [createArchive.flatList]
        createArchiveOption.action = handleCreateArchive
        return createArchiveOption
    }
    public func handleCreateArchive(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        guard let paths = argumentIndex[createArchive.command.keys.first!] else {
            throw XcodeHelperError.createArchive(message: "You didn't provide any paths.")
        }
        guard let archivePath = paths.first else {
            throw XcodeHelperError.createArchive(message: "You didn't provide the archive path.")
        }
        guard paths.count > 1 else {
            throw XcodeHelperError.createArchive(message: "You didn't provide any files to archive.")
        }
        var flatList = false
        if let _ = argumentIndex[createArchive.flatList.keys.first!]?.first {
            flatList = true
        }
        
        let filePaths = Array(paths[1..<paths.count])
        try xcodeHelpable.createArchive(at: archivePath, with: filePaths, flatList: flatList)
    }
    
    
    // MARK: UploadArchive
    struct uploadArchive {
        static let command              = CliOption(keys: ["upload-archive", "UPLOAD_ARCHIVE"],
                                                    description: "Upload an archive to S3",
                                                    usage: "xchelper upload-archive ARCHIVE_PATH [OPTIONS]. ARCHIVE_PATH the path of the archive that you want to upload to S3.",
                                                    requiresValue: true,
                                                    defaultValue:nil)
        static let bucket               = CliOption(keys:["-b", "--bucket", "UPLOAD_ARCHIVE_S3_BUCKET"],
                                                    description:"The bucket that you want to upload your archive to.",
                                                    usage: nil,
                                                    requiresValue:true,
                                                    defaultValue:nil)
        static let region               = CliOption(keys:["-r", "--region", "UPLOAD_ARCHIVE_S3_REGION"],
                                                    description:"The bucket's region.",
                                                    usage: nil,
                                                    requiresValue:true,
                                                    defaultValue:"us-east-1")
        static let key                  = CliOption(keys:["-k", "--key", "UPLOAD_ARCHIVE_S3_KEY"],
                                                    description:"The S3 key for the bucket.",
                                                    usage: nil,
                                                    requiresValue:true,
                                                    defaultValue:nil)
        static let secret               = CliOption(keys:["-s", "--secret", "UPLOAD_ARCHIVE_S3_SECRET"],
                                                    description:"The secret for the key.",
                                                    usage: nil,
                                                    requiresValue:true,
                                                    defaultValue:nil)
        static let credentialsFile      = CliOption(keys:["-d", "--credentials", "UPLOAD_ARCHIVE_CREDENTIALS"],
                                                    description:"The secret for the key.",
                                                    usage: nil,
                                                    requiresValue:true,
                                                    defaultValue:nil)
    }
    public var uploadArchiveOption: CliOption {
        var uploadArchveOption = uploadArchive.command
        uploadArchveOption.requiredArguments = [uploadArchive.bucket, uploadArchive.region]//(key,secret) OR credentials check in handler
        return uploadArchveOption
    }
    public func handleUploadArchive(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        guard let archivePath = argumentIndex[uploadArchive.command.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the path to the archive that you want to upload.")
        }
        guard let bucket = argumentIndex[uploadArchive.bucket.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the S3 bucket to upload to.")
        }
        guard let region = argumentIndex[uploadArchive.region.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the region for the bucket.")
        }
        
        if let key = argumentIndex[uploadArchive.key.keys.first!]?.first {
            guard let secret = argumentIndex[uploadArchive.secret.keys.first!]?.first else {
                throw XcodeHelperError.uploadArchive(message: "You didn't provide the secret for the key.")
            }
            try xcodeHelpable.uploadArchive(at: archivePath, to: bucket, in: region, key: key, secret: secret)
            
        } else if let file = argumentIndex[uploadArchive.credentialsFile.keys.first!]?.first {
                try xcodeHelpable.uploadArchive(at: archivePath, to: bucket, in: region, using: file)
            
        } else {
            throw XcodeHelperError.uploadArchive(message: "You must provide either a credentials file or a key and secret")
        }
    }
    
    
    // MARK: GitTag
    struct gitTag {
        static let command              = CliOption(keys: ["git-tag", "GIT_TAG"],
                                                    description: "Update your package's git repo's semantic versioned tag",
                                                    usage: "xchelper git-tag [OPTIONS]",
                                                    requiresValue: false,
                                                    defaultValue: nil)
        static let changeDirectory      = CliOption(keys:["-d", "--chdir", "GIT_TAG_CHDIR"],
                                                    description:"Change the current working directory.",
                                                    usage:nil,
                                                    requiresValue:true,
                                                    defaultValue:nil)
        static let versionOption        = CliOption(keys: ["-v", "--version", "GIT_TAG_VERSION"],
                                                    description: "Specify exactly what the version should be.",
                                                    usage: nil,
                                                    requiresValue: true,
                                                    defaultValue: nil)
        static let incrementOption      = CliOption(keys: ["-i", "--increment", "GIT_TAG_INCREMENT"],
                                                    description: "Automatically increment a portion of the repo's tag. Valid values are [major, minor, patch]",
                                                    usage: nil,
                                                    requiresValue: true,
                                                    defaultValue: "patch")
        static let pushOption           = CliOption(keys: ["-p", "--push", "GIT_TAG_PUSH"],
                                                    description: "Push your tag with `git push && git push origin #.#.#`",
                                                    usage: nil,
                                                    requiresValue: false,
                                                    defaultValue: nil)
    }
    public var gitTagOption: CliOption {
        var gitTagOption = gitTag.command
        gitTagOption.optionalArguments = [gitTag.changeDirectory, gitTag.versionOption, gitTag.incrementOption, gitTag.pushOption]
        gitTagOption.action = handleGitTag
        return gitTagOption
    }
    public func handleGitTag(option:CliOption) throws {
        let argumentIndex = option.argumentIndex
        let sourcePath = parseSourceCodePath(from: argumentIndex, with: gitTag.changeDirectory.keys.first!)
        var outputString: String?
        do {
            var versionString: String?

            //update from user input
            if let version = argumentIndex[gitTag.versionOption.keys.first!]?.first {
                try xcodeHelpable.gitTag(version, repo: sourcePath)
                versionString = version
                
            }else{
                guard let componentString = argumentIndex[gitTag.incrementOption.keys.first!]?.first else {
                    throw XcodeHelperError.gitTagParse(message: "You must provide either \(gitTag.versionOption.keys) OR \(gitTag.incrementOption.keys)")
                }
                guard let component = GitTagComponent(stringValue: componentString) else {
                    throw XcodeHelperError.gitTagParse(message: "Unknown value \(componentString)")
                }
                versionString = try xcodeHelpable.incrementGitTag(component: component, at: sourcePath)
            }

            if let tag = versionString {
                outputString = tag
                if argumentIndex[gitTag.pushOption.keys.first!] != nil {
                    try xcodeHelpable.pushGitTag(tag: tag, at: sourcePath)
                }
            }

        } catch XcodeHelperError.gitTag(_) {
            //no current tag, just start it at 0.0.1
            outputString = "0.0.1"
            try xcodeHelpable.gitTag(outputString!, repo: sourcePath)
        }
        
        if let str = outputString {
            print(str)
        }
    }
    
    
    // MARK: CreateXcarchive
    struct createXcarchive {
        
        static let command              = CliOption(keys: ["create-xcarchive", "CREATE_XCARCHIVE"],
                                                    description: "Store your built binary in an xcarchive where Xcode's Organizer can keep track",
                                                    usage: "xchelper create-xcarchive-plist XCARCHIVE_PATH [OPTIONS]. XCARCHIVE_PATH is the directory (.xcarchive) where you want the Info.plist created in. ",
                                                    requiresValue: true,
                                                    defaultValue: nil)
        static let nameOption          = CliOption(keys: ["-n", "--name", "CREATE_PLIST_APP_NAME"],
                                                   description: "The app name to include in the `Name` field of the Info.plist.",
                                                   usage: nil,
                                                   requiresValue: true,
                                                   defaultValue: nil)
        static let schemeOption          = CliOption(keys: ["-s", "--scheme", "CREATE_PLIST_SCHEME"],
                                                     description: "The scheme name to include in the `Scheme` field of the Info.plist.",
                                                     usage: nil,
                                                     requiresValue: true,
                                                     defaultValue: nil)
    }
    public var createXcarchiveOption: CliOption {
        var createXcarchiveOption = createXcarchive.command
        createXcarchiveOption.requiredArguments = [createXcarchive.nameOption, createXcarchive.schemeOption]
        createXcarchiveOption.action = handleCreateArchive
        return createXcarchiveOption
    }
    //returns the path to the new xcarchive
    public func handleCreateXcarchive(option:CliOption) throws -> String {
        let argumentIndex = option.argumentIndex
        guard let archivePath = argumentIndex[createXcarchive.command.keys.first!]?.first else {
            throw XcodeHelperError.createXcarchive(message: "You didn't provide the path to the xcarchive.")
        }
        guard let name = argumentIndex[createXcarchive.nameOption.keys.first!]?.first else {
            throw XcodeHelperError.createXcarchive(message: "You didn't provide the name to include in the plist.")
        }
        guard let scheme = argumentIndex[createXcarchive.schemeOption.keys.first!]?.first else {
            throw XcodeHelperError.createXcarchive(message: "You didn't provide the scheme to include in the plist.")
        }
        return try xcodeHelpable.createXcarchive(in: archivePath, with: name, from: scheme)
    }
    
}
