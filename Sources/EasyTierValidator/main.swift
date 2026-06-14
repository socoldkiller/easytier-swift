import EasyTierSupport
import Foundation

let command = CommandLine.arguments.dropFirst().first

guard command == "validate" else {
    FileHandle.standardError.write(Data("usage: EasyTierValidator validate\n".utf8))
    exit(64)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let toml = String(data: input, encoding: .utf8), !toml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    FileHandle.standardError.write(Data("empty EasyTier config\n".utf8))
    exit(65)
}

do {
    let config = try NetworkConfigTOMLCodec.decode(toml)
    try NetworkConfigValidator.validate(config)
    exit(0)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
