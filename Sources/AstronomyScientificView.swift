import SwiftUI
import Charts

// Domain views use the actual computed samples; geometric diagrams name their coordinate model.
struct AstronomyScientificView: View {
    let picture: AstronomyPicture
    @State private var rotation = 0.0
    @State private var radiusScale = 1.0
    @State private var inclination = 90.0
    @State private var transitQuery: String?
    @State private var transitSeries: AstronomySeries?
    @State private var calculating = false
    private var kind: String { picture.data["kind"] as? String ?? "panel" }
    private func number(_ key: String, _ fallback: Double = 0) -> Double { picture.data[key] as? Double ?? fallback }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if kind == "sky" {
                sky.frame(height: 330)
                HStack { Text("Rotate sky"); AstronomySlider(value: $rotation, range: -Double.pi...Double.pi) }
                Text("North at top · East at right · Outer circle is the horizon · Faint objects lie below it")
                    .font(.caption).foregroundStyle(.secondary)
            } else if kind == "black_hole" {
                blackHole.frame(height: 290)
            } else if kind == "spectrum" {
                spectrum.frame(height: 200)
            } else if kind == "comparison" {
                comparison.frame(height: 200)
            } else if kind == "habitable" {
                habitable.frame(height: 250)
            } else if kind == "potential" {
                potential.frame(height: 300)
            } else if kind == "image" {
                image.frame(height: 280)
                Text("Preview: \(Int(number("width"))) × \(Int(number("height"))) pixels; display uses 1–99% intensity stretch")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if kind == "transit_controls" {
                if let series = transitSeries ?? picture.series { AstronomyCurve(series: series).frame(height: 250) }
                HStack { Text("Planet radius ×\(radiusScale, specifier: "%.2f")").frame(width: 155, alignment: .leading)
                    AstronomySlider(value: $radiusScale, range: 0.2...3, committed: updateTransit) }
                HStack { Text("Inclination \(inclination, specifier: "%.3f")°").frame(width: 155, alignment: .leading)
                    AstronomySlider(value: $inclination, range: 85...90, committed: updateTransit) }
                Text(calculating ? "Recomputing limb-darkened transit…" : "Quadratic limb darkening; radius and inclination are observer geometry controls")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let series = picture.series { AstronomyCurve(series: series).frame(height: series.kind == "orbit" ? 320 : 260) }
            if kind == "panel", picture.series == nil { resultRows }
        }
        .onAppear { inclination = number("inclination", 90) }
        .onReceive(NotificationCenter.default.publisher(for: AstronomyEngine.changed)) { notice in
            guard let query = transitQuery, notice.object as? String == query else { return }
            if case .scientific(let p)? = AstronomyEngine.shared.answer(query).details?.diagram {
                transitSeries = p.series; calculating = false
            }
        }
    }

    private var resultRows: some View {
        let rows = Self.rows(picture.result)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    Text(row.0.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    Text(row.1).fontDesign(.monospaced).textSelection(.enabled)
                }.font(.system(size: 12))
            }
            if rows.count > 40 { Text("Copy the result for all \(rows.count) values.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    static func rows(_ value: Any, prefix: String = "") -> [(String,String)] {
        if let object = value as? [String:Any] {
            if let number = object["value"] as? NSNumber { return [(prefix,String(format: "%.8g",number.doubleValue) + " " + (object["unit"] as? String ?? ""))] }
            return object.keys.sorted().flatMap { key in rows(object[key]!, prefix: prefix.isEmpty ? key : prefix + "." + key) }
        }
        if let array = value as? [Any] {
            if array.count > 40 { return [(prefix,"\(array.count) samples; copy result to export") ] }
            return array.enumerated().flatMap { rows($0.element,prefix:prefix + "[\($0.offset)]") }
        }
        if let number = value as? NSNumber { return [(prefix,String(format:"%.8g",number.doubleValue))] }
        return [(prefix,String(describing:value))]
    }
    private func updateTransit() {
        let d = picture.data
        let a = number("a"), rs = number("star_radius"), rp = number("planet_radius") * radiusScale
        let period = number("period") * 86400
        // Recover μ from P and a, avoiding a silent solar-mass assumption for custom host stars.
        let mu = 4 * Double.pi * Double.pi * a * a * a / (period * period)
        let times = d["times"] as? [Double] ?? []
        let limb = d["limb_darkening"] as? [Double] ?? [0.3,0.2]
        let query = "@ transit_light_curve(\(rp) m, \(rs) m, {a:\(a) m,e:\(number("e")),central_mass:\(mu / 6.67430e-11) kg}, [" + times.map { "\($0) day" }.joined(separator: ",") + "], geometry:{inclination:\(inclination) deg,argp:\(number("argp")) deg,limb_darkening:[\(limb.map(String.init(describing:)).joined(separator:","))]})"
        // Named arguments use '=' in calls, ':' only in object literals.
        let fixed = query.replacingOccurrences(of: "geometry:{", with: "geometry={")
        transitQuery = fixed; calculating = true
        let answer = AstronomyEngine.shared.answer(fixed)
        if case .scientific(let p)? = answer.details?.diagram { transitSeries = p.series; calculating = false }
    }
    private var sky: some View {
        Canvas { ctx,size in
            let center = CGPoint(x:size.width/2,y:size.height/2), r = min(size.width,size.height)/2-30
            for fraction in [1.0,0.6667,0.3333] {
                ctx.stroke(Path(ellipseIn:CGRect(x:center.x-r*fraction,y:center.y-r*fraction,width:2*r*fraction,height:2*r*fraction)),with:.color(.secondary.opacity(0.3)),lineWidth:1)
            }
            for (i,name) in ["N","E","S","W"].enumerated() {
                let a = Double(i)*Double.pi/2+rotation
                draw(ctx,name,CGPoint(x:center.x+(r+17)*sin(a),y:center.y-(r+17)*cos(a)))
            }
            let points = picture.data["points"] as? [[String:Any]] ?? []
            var occupied: [CGRect] = []
            for item in points {
                let alt = item["alt"] as? Double ?? 0, az = (item["az"] as? Double ?? 0)+rotation
                let rr = r*(1-min(max(alt,0),Double.pi/2)/(Double.pi/2))
                let p = CGPoint(x:center.x+rr*sin(az),y:center.y-rr*cos(az))
                let color:Color = alt >= 0 ? .accentColor : .secondary.opacity(0.4)
                ctx.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(color))
                safeLabel(ctx,item["label"] as? String ?? "",point:p,size:size,color:color,occupied:&occupied)
            }
        }
    }
    private var blackHole: some View {
        Canvas { ctx,size in
            let horizon = number("horizon"), isco = number("isco",horizon*3), photon = picture.data["photon"] as? Double
            let maxR = max(horizon,isco,photon ?? 0)*1.12, scale = min(size.width*0.35,size.height*0.4)/maxR
            let center = CGPoint(x:size.width*0.4,y:size.height*0.46)
            for (radius,name,color) in [(isco,"Equatorial ISCO",Color.blue),(photon ?? 0,"Photon sphere (Schwarzschild)",Color.orange),(horizon,"Outer event horizon",Color.primary)] where radius>0 {
                let rr=radius*scale; let path=Path(ellipseIn:CGRect(x:center.x-rr,y:center.y-rr,width:rr*2,height:rr*2))
                if name.contains("horizon") { ctx.fill(path,with:.color(.primary.opacity(0.8))) } else { ctx.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:1.3,dash:[5,3])) }
                draw(ctx,"\(name): \(Format.number(radius)) m",CGPoint(x:8,y:size.height-55+CGFloat(name.contains("horizon") ? 0 : name.contains("Photon") ? 17 : 34)),color:color,anchor:.leading)
            }
            let spin=number("spin")
            draw(ctx,spin == 0 ? "Schwarzschild · concentric radii to scale" : "Kerr a* = \(spin) · Boyer–Lindquist radii",CGPoint(x:8,y:15),anchor:.leading)
            if spin != 0 { draw(ctx,"Equatorial radius schematic; Kerr has no single photon sphere",CGPoint(x:8,y:35),anchor:.leading) }
        }
    }
    private var spectrum: some View {
        Canvas { ctx,size in
            let em=number("emitted")/1e-9, ob=number("observed")/1e-9
            let lo=min(em,ob)*0.8, hi=max(em,ob)*1.2
            for (v,title,y,color) in [(em,"Emitted",60.0,Color.blue),(ob,"Observed",125.0,Color.red)] {
                var line=Path(); line.move(to:CGPoint(x:25,y:y)); line.addLine(to:CGPoint(x:size.width-20,y:y)); ctx.stroke(line,with:.color(.secondary.opacity(0.3)),lineWidth:2)
                let x=25+(v-lo)/(hi-lo)*(size.width-45); var marker=Path(); marker.move(to:CGPoint(x:x,y:y-18)); marker.addLine(to:CGPoint(x:x,y:y+18)); ctx.stroke(marker,with:.color(color),lineWidth:3)
                draw(ctx,"\(title): \(Format.number(v)) nm",CGPoint(x:25,y:y-30),color:color,anchor:.leading)
            }
            draw(ctx,"z = \(Format.number(number("z"))) · Wavelength increases →",CGPoint(x:25,y:180),anchor:.leading)
        }
    }
    private var comparison: some View {
        Canvas { ctx,size in
            let values=picture.data["values"] as? [Double] ?? [1,1], labels=picture.data["labels"] as? [String] ?? ["First","Second"]
            let maxV=max(values.max() ?? 1,1e-100); let property=picture.data["property"] as? String ?? ""
            for i in values.indices {
                let x=size.width*(i==0 ? 0.25 : 0.72), v=values[i]/maxV
                if ["radius","diameter"].contains(property) {
                    let r=70*v; ctx.fill(Path(ellipseIn:CGRect(x:x-r,y:90-r,width:2*r,height:2*r)),with:.color(i==0 ? .blue : .orange))
                } else { ctx.fill(Path(CGRect(x:x-30,y:150-120*v,width:60,height:120*v)),with:.color(i==0 ? .blue : .orange)) }
                draw(ctx,labels.indices.contains(i) ? labels[i] : "Body",CGPoint(x:x,y:173))
                draw(ctx,Format.number(values[i])+" "+(picture.data["unit"] as? String ?? ""),CGPoint(x:x,y:191))
            }
        }
    }
    private var habitable: some View {
        Canvas { ctx,size in
            let inner=number("inner"), outer=number("outer"), scale=min(size.height,size.width)*0.43/outer
            let center=CGPoint(x:size.width/2,y:size.height/2)
            let r=outer*scale,ri=inner*scale
            var ring=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:2*r,height:2*r))
            ring.addEllipse(in:CGRect(x:center.x-ri,y:center.y-ri,width:2*ri,height:2*ri));ctx.fill(ring,with:.color(.green.opacity(0.25)),style:FillStyle(eoFill:true))
            ctx.fill(Path(ellipseIn:CGRect(x:center.x-6,y:center.y-6,width:12,height:12)),with:.color(.orange))
            draw(ctx,"\(Format.number(inner)) – \(Format.number(outer)) AU",CGPoint(x:10,y:15),anchor:.leading)
            draw(ctx,"Solar-spectrum flux limits; no planetary climate model",CGPoint(x:10,y:size.height-10),anchor:.leading)
        }
    }
    private var potential: some View {
        Canvas { ctx,size in
            let mu=number("mu"); let nx=110,ny=80
            for iy in 0..<ny { for ix in 0..<nx {
                let x = -1.6 + 3.2*Double(ix)/Double(nx), y = -1.2 + 2.4*Double(iy)/Double(ny)
                let r1=max(hypot(x+mu,y),0.015),r2=max(hypot(x-1+mu,y),0.015)
                let omega=(x*x+y*y)/2+(1-mu)/r1+mu/r2
                let intensity=min(1,max(0,(omega-1.3)/2))
                ctx.fill(Path(CGRect(x:Double(ix)*size.width/Double(nx),y:Double(ny-iy-1)*size.height/Double(ny),width:size.width/Double(nx)+1,height:size.height/Double(ny)+1)),with:.color(Color(hue:0.65-0.55*intensity,saturation:0.65,brightness:0.35+0.55*intensity)))
            } }
            let points=picture.data["points"] as? [[Double]] ?? []
            var occupied: [CGRect] = []
            for (i,p) in points.enumerated() where p.count>=2 {
                let point=CGPoint(x:(p[0]+1.6)/3.2*size.width,y:(1.2-p[1])/2.4*size.height)
                ctx.fill(Path(ellipseIn:CGRect(x:point.x-3,y:point.y-3,width:6,height:6)),with:.color(.white)); safeLabel(ctx,"L\(i+1)",point:point,size:size,color:.white,occupied:&occupied)
            }
            draw(ctx,"Ω = (x²+y²)/2 + (1−μ)/r₁ + μ/r₂ · separation units",CGPoint(x:10,y:size.height-12),color:.white,anchor:.leading)
        }
    }
    private var image: some View {
        Canvas { ctx,size in
            let pixels=picture.data["pixels"] as? [[Double]] ?? []; let rows=pixels.count,cols=pixels.first?.count ?? 0
            guard rows>0,cols>0 else { return }
            let lo=number("low"),hi=max(number("high"),lo+1e-12); let scale=min(size.width/Double(cols),size.height/Double(rows)); let left=(size.width-Double(cols)*scale)/2
            for y in 0..<rows { for x in 0..<min(cols,pixels[y].count) {
                let v=min(1,max(0,(pixels[y][x]-lo)/(hi-lo)));ctx.fill(Path(CGRect(x:left+Double(x)*scale,y:Double(y)*scale,width:scale+0.5,height:scale+0.5)),with:.color(Color(white:v)))
            } }
        }
    }
    private func safeLabel(_ ctx: GraphicsContext,_ text: String,point: CGPoint,size: CGSize,color: Color,occupied: inout [CGRect]) {
        let width = CGFloat(text.count)*6.2+6
        var box = CGRect(x:point.x+7,y:point.y-14,width:width,height:15)
        for attempt in 0..<24 {
            let offset = CGFloat((attempt+1)/2)*16*(attempt%2 == 0 ? 1 : -1)
            let candidate = CGRect(x:min(max(8,point.x+7),size.width-width-8),y:min(max(8,point.y-14+offset),size.height-24),width:width,height:15)
            box=candidate
            if !occupied.contains(where: { $0.insetBy(dx:-2,dy:-2).intersects(candidate) }) { break }
        }
        occupied.append(box)
        if abs(box.midY-point.y)>14 {
            var leader=Path();leader.move(to:point);leader.addLine(to:CGPoint(x:box.minX,y:box.midY))
            ctx.stroke(leader,with:.color(color.opacity(0.5)),lineWidth:0.6)
        }
        draw(ctx,text,CGPoint(x:box.minX,y:box.midY),color:color,anchor:.leading)
    }
    private func draw(_ ctx: GraphicsContext,_ s: String,_ point: CGPoint,color:Color = .secondary,anchor:UnitPoint = .center) {
        ctx.draw(Text(s).font(.system(size:11)).foregroundColor(color),at:point,anchor:anchor)
    }
}

struct AstronomyCurve: View {
    let series: AstronomySeries
    var body: some View {
        Chart {
            ForEach(series.x.indices,id:\.self) { i in
                LineMark(x:.value(series.xLabel,series.x[i]),y:.value(series.yLabel,series.y[i]))
                    .interpolationMethod(.linear)
            }
            if series.kind == "orbit" { PointMark(x:.value(series.xLabel,0),y:.value(series.yLabel,0)).foregroundStyle(.orange).symbolSize(80) }
        }
        .chartXAxisLabel(series.xLabel).chartYAxisLabel(series.yLabel)
        .chartXScale(domain: extent(series.kind == "orbit" ? series.x + series.y : series.x)).chartYScale(domain: extent(series.kind == "orbit" ? series.x + series.y : series.y))
        .chartPlotStyle { plot in
            if series.kind == "orbit" { plot.background(.primary.opacity(0.025)).aspectRatio(1,contentMode:.fit) }
            else { plot.background(.primary.opacity(0.025)) }
        }
        .accessibilityLabel(series.label)
    }
    private func extent(_ values:[Double]) -> ClosedRange<Double> {
        let lo=values.min() ?? 0, hi=values.max() ?? 1
        let pad=max((hi-lo)*0.05,max(abs(hi),1e-30)*0.001)
        return (lo-pad)...(hi+pad)
    }
}

// SwiftUI-only control works in the non-key Spotlight panel and in exported previews.
private struct AstronomySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var committed: () -> Void = {}
    var body: some View {
        GeometryReader { geometry in
            let width = max(1,geometry.size.width - 14)
            let position = min(1,max(0,(value-range.lowerBound)/(range.upperBound-range.lowerBound))) * width
            ZStack(alignment:.leading) {
                Capsule().fill(.secondary.opacity(0.2)).frame(height:4)
                Capsule().fill(Color.accentColor).frame(width:position+7,height:4)
                Circle().fill(Color.accentColor).frame(width:14,height:14).offset(x:position)
            }.frame(height:24).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { gesture in
                    value = range.lowerBound + min(1,max(0,(gesture.location.x-7)/width))*(range.upperBound-range.lowerBound)
                }.onEnded { _ in committed() })
                .accessibilityElement().accessibilityLabel("Value").accessibilityValue(String(format:"%.3f",value))
                .accessibilityAdjustableAction { direction in
                    let step=(range.upperBound-range.lowerBound)/100
                    value=min(range.upperBound,max(range.lowerBound,value+(direction == .increment ? step : -step)))
                    committed()
                }
        }.frame(height:24)
    }
}
