import AppKit

// `Edgelit --preview <folder>` draws sample frames to PNG files and exits (used to check the artwork).
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    Preview.write(to: CommandLine.arguments[i + 1])
    exit(0)
}

if CommandLine.arguments.contains("--bench") { Preview.bench(); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
