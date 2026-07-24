import Foundation
import RealityKit

@main
struct PhotogrammetryCLI {
    static let usage = """
    Usage: photogrammetry <input-folder> <output.usdz> [options]

      <input-folder>   Folder of photos (HEIC/JPEG/PNG) of one object
      <output.usdz>    Output model path (must end in .usdz)

    Options:
      -d, --detail <level>       preview | reduced | medium | full | raw   (default: full)
      -o, --ordering <mode>      unordered | sequential                    (default: unordered)
      -f, --sensitivity <mode>   normal | high                             (default: normal)

    Example:
      ./photogrammetry ./photos ./model.usdz -d full -f high
    """

    static func main() async {
        guard PhotogrammetrySession.isSupported else {
            fputs("Error: Photogrammetry is not supported on this Mac.\n", stderr)
            exit(1)
        }

        var positional: [String] = []
        var detail = PhotogrammetrySession.Request.Detail.full
        var config = PhotogrammetrySession.Configuration()

        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "-h", "--help":
                print(usage); exit(0)
            case "-d", "--detail":
                guard !args.isEmpty else { die("Missing value for \(arg)") }
                switch args.removeFirst() {
                case "preview":  detail = .preview
                case "reduced":  detail = .reduced
                case "medium":   detail = .medium
                case "full":     detail = .full
                case "raw":      detail = .raw
                default: die("Invalid detail level")
                }
            case "-o", "--ordering":
                guard !args.isEmpty else { die("Missing value for \(arg)") }
                switch args.removeFirst() {
                case "unordered":  config.sampleOrdering = .unordered
                case "sequential": config.sampleOrdering = .sequential
                default: die("Invalid ordering")
                }
            case "-f", "--sensitivity":
                guard !args.isEmpty else { die("Missing value for \(arg)") }
                switch args.removeFirst() {
                case "normal": config.featureSensitivity = .normal
                case "high":   config.featureSensitivity = .high
                default: die("Invalid sensitivity")
                }
            default:
                positional.append(arg)
            }
        }

        guard positional.count == 2 else {
            print(usage); exit(positional.isEmpty ? 0 : 1)
        }
        let inputURL = URL(fileURLWithPath: positional[0], isDirectory: true)
        let outputURL = URL(fileURLWithPath: positional[1])
        guard outputURL.pathExtension.lowercased() == "usdz" else {
            die("Output path must end in .usdz (convert to STL in Blender afterward)")
        }
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            die("Input folder not found: \(inputURL.path)")
        }

        do {
            let session = try PhotogrammetrySession(input: inputURL, configuration: config)
            let watcher = Task {
                var lastPercent = -1
                for try await output in session.outputs {
                    switch output {
                    case .inputComplete:
                        print("Photos ingested, reconstructing…")
                    case .requestProgress(_, let fraction):
                        let percent = Int(fraction * 100)
                        if percent != lastPercent {
                            lastPercent = percent
                            print("\rProgress: \(percent)%", terminator: percent == 100 ? "\n" : "")
                            fflush(stdout)
                        }
                    case .invalidSample(let id, let reason):
                        print("\nSkipped image \(id): \(reason)")
                    case .automaticDownsampling:
                        print("\nNote: images were downsampled to fit in memory")
                    case .requestError(_, let error):
                        fputs("\nReconstruction error: \(error)\n", stderr)
                    case .requestComplete(_, .modelFile(let url)):
                        print("Model written to \(url.path)")
                    case .processingComplete:
                        print("Done.")
                    default:
                        break
                    }
                }
            }
            try session.process(requests: [.modelFile(url: outputURL, detail: detail)])
            try await watcher.value
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func die(_ message: String) -> Never {
        fputs("Error: \(message)\n\n\(usage)\n", stderr)
        exit(1)
    }
}
