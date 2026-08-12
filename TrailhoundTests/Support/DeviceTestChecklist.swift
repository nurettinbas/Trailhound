import Foundation

/// Manual device test checklist — run on a real phone after each release candidate.
enum DeviceTestChecklist {
    static let items = [
        "30+ min real drive: distance and duration advance",
        "Background the app, wait 5 min: recording continues",
        "Shortcuts: recording starts when connecting to the car",
        "Shortcuts: recording stops when leaving the car",
        "Force-quit → reopen → orphan banner / recovery",
        "Detail map route looks realistic (does not cross water)",
        "Pairing: typing a vehicle name keeps the keyboard smooth",
        "While recording, switching away from Trips reduces jank",
        "Long trip detail opens without freezing",
        "50 km trip detail: DevLog points/displayPts/colorSegs; colorSegs ≤ 60",
        "500 km trip detail (if available): opens smoothly, curves not oversimplified",
        "Second open of the same long trip is instant (memory cache)",
        "App kill → reopen → long trip detail still fast (disk cache)",
        "After GPS trim, map updates (cache invalidation)",
        "After merge, combined route draws correctly",
        "Trip with tunnel/signal loss keeps a broken route (no bird-flight fill)",
        "Start-side Select: photo/icon + chevron only; no name text overflow",
        "Recording card: large vehicle photo; Stop uses stop.fill",
        "Vespa / motorcycle / car markers face right on the road",
        "Dynamic Island + lock banner: vehicle photo or correct SF; facing right",
        "Notifications: live recording card shows road + photo + controls",
        "Pause/resume: no road remount; Island photo stays",
        "Home-screen widget: Pause → Resume label flips; Resume → Pause returns",
        "Lock banner pause/resume: icon+color immediate; widget switches to Resume",
        "Recording with vehicle photo: Island shows photo; DevLog ‘photo attached (N B)’",
        "Light/white vehicle photo: if punch makes it vanish, original photo is shown",
        "Vehicle without photo: Island + notification card fall back to SF symbol",
        "Expanded Island: no top gap; bottom buttons not clipped (even at 1:00:10)",
        "Vehicle picker menu: row icons face right; checkmark stays on selection",
        "Vehicle photo: Add → Library/Camera chooser; Library/Camera single sheet expand (~72%), no dismiss/reopen",
        "Vehicle photo: Capture Back → shrinks to chooser; Cancel on chooser dismisses sheet",
        "Vehicle photo: All Photos system picker; framing after pick",
        "Vehicle photo: camera shutter; green privacy dot clears when backgrounded",
        "Vehicle photo: limited library / deny photos / deny camera states",
        "Vehicle photo: Change + existing framing Apply/Save path still works"
    ]
}
