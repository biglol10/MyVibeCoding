import Foundation

enum ProcessCommand {
    static func run(_ executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? executablePath
            throw SamplerError.commandFailed(message)
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
