import CoreLocation

/// Work on the provider's road geometry; never reshape its turns with splines.
enum NavigationRouteGeometry {
    struct Match {
        let coordinate: CLLocationCoordinate2D
        let distance: Double
        let progress: Double
    }
    static func usableLocation(_ location: CLLocation, previous: CLLocation?, now: Date = Date()) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              abs(now.timeIntervalSince(location.timestamp)) <= 15 else { return false }
        if let previous {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return false }
            if seconds < 15 && location.distance(from: previous) > max(100, seconds * 65) { return false }
        }
        return true
    }
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    static func match(_ point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D]) -> Match? {
        guard path.count > 1 else { return nil }
        var best: Match?
        var progress = 0.0
        let scale = cos(point.latitude * .pi / 180)
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let dx = (b.longitude - a.longitude) * scale, dy = b.latitude - a.latitude
            let length2 = dx * dx + dy * dy
            let t = length2 > 0 ? max(0, min(1, (((point.longitude - a.longitude) * scale * dx) + (point.latitude - a.latitude) * dy) / length2)) : 0
            let projected = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
            let offset = distance(point, projected), length = distance(a, b)
            if best == nil || offset < best!.distance { best = Match(coordinate: projected, distance: offset, progress: progress + t * length) }
            progress += length
        }
        return best
    }
    static func coordinate(at progress: Double, path: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard let first = path.first else { return nil }
        var remaining = max(0, progress)
        if remaining == 0 { return first }
        for i in 0..<max(0, path.count - 1) {
            let a = path[i], b = path[i + 1], length = distance(a, b)
            if remaining <= length && length > 0 {
                let t = remaining / length
                return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
            }
            remaining -= length
        }
        return path.last
    }
    static func snapped(_ point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard let match = match(point, path: path), match.distance <= 40 else { return point }
        return match.coordinate
    }
    static func heading(at point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D]) -> Double? {
        guard let match = match(point, path: path), match.distance <= 75,
              let ahead = coordinate(at: match.progress + 25, path: path), distance(match.coordinate, ahead) > 2 else { return nil }
        let a = match.coordinate.latitude * .pi / 180, b = ahead.latitude * .pi / 180
        let delta = (ahead.longitude - match.coordinate.longitude) * .pi / 180
        return (atan2(sin(delta) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(delta)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    static func instructionIndex(progress: Double, stepEnds: [Double]) -> Int {
        guard !stepEnds.isEmpty else { return 0 }
        return stepEnds.firstIndex(where: { progress <= $0 + 5 }) ?? (stepEnds.count - 1)
    }
    static func easedHeading(from current: Double, to target: Double) -> Double {
        let delta = (target - current + 540).truncatingRemainder(dividingBy: 360) - 180
        return (current + delta * 0.7 + 360).truncatingRemainder(dividingBy: 360)
    }
}
