import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, behaves like a menu-bar/background utility
app.run()
