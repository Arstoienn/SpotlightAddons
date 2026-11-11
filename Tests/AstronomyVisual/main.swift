import AppKit
import SwiftUI

try MainActor.assumeIsolated {
// Noninteractive render test; no Accessibility permission, Spotlight manipulation or app install.
AstronomyEngine.synchronous = true
let queries = [
    "@ orbit(earth,sun,at=\"2026-11-11\")",
    "@ hr_position(sun)",
    "@ schwarzschild_radius(10 M_sun)",
    "@ kerr_horizon_radius(10 M_sun,0.9)",
    "@ blackbody_spectrum(5772 K)",
    "@ redshift(500 nm,600 nm)",
    "@ sky_map({longitude:121.56 deg,latitude:25.03 deg},\"2026-11-11T12:00:00\")",
    "@ transit_light_curve(jupiter,sun,{a:0.05 AU,central_mass:sun},[-0.15 day,-0.1 day,-0.05 day,-0.02 day,0 day,0.02 day,0.05 day,0.1 day,0.15 day])",
    "@ compare(earth,jupiter,radius)",
    "@ lagrange_points(sun,earth)",
    "@ habitable_zone(sun)",
    "@ estimate_background([[1,2,1,1,1],[1,2,3,2,1],[1,3,10,3,1],[1,2,3,2,1],[1,1,1,1,1]])"
]
let directory = CommandLine.arguments.dropFirst().first ?? "build/astronomy-previews"
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
let _ = NSApplication.shared
for (index,query) in queries.enumerated() {
    guard let answer = Astronomy.parse(query), let diagram = answer.details?.diagram else { fatalError("No diagram for \(query)") }
    let content = VStack(alignment:.leading,spacing:16) {
        Text(query).font(.system(size:13,design:.monospaced)).lineLimit(2)
        Text(diagram.title).font(.title3.bold())
        AstroDiagramView(diagram:diagram)
        Text(answer.solution.exact).font(.system(size:12,design:.monospaced)).lineLimit(3)
    }.padding(24).frame(width:760).background(Color.white).environment(\.colorScheme,.light)
    let renderer = ImageRenderer(content:content); renderer.scale = 2
    guard let image = renderer.cgImage else { fatalError("Render failed for \(query)") }
    let rep=NSBitmapImageRep(cgImage:image)
    guard let png=rep.representation(using:.png,properties:[:]) else { fatalError("PNG failed") }
    let file=URL(fileURLWithPath:directory).appendingPathComponent(String(format:"%02d",index+1)+".png")
    try png.write(to:file)
    print(file.path)
}

}
