import Foundation

public enum SamplerError: Error, Equatable {
    case commandFailed(String)
    case invalidOutput(String)
    case systemCallFailed(String)
    case unavailable(String)
}
