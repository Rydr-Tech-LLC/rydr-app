import SwiftUI
import MapKit
import CoreLocation
import UIKit

enum DriverNavigationProvider: String, CaseIterable, Identifiable {
    case rydr
    case appleMaps
    case googleMaps
    case waze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rydr: return "Rydr Map"
        case .appleMaps: return "Apple Maps"
        case .googleMaps: return "Google Maps"
        case .waze: return "Waze"
        }
    }

    var subtitle: String {
        switch self {
        case .rydr:
            return "In-app navigation. Default for all drivers."
        case .appleMaps:
            return "Open turn-by-turn directions in Apple Maps."
        case .googleMaps:
            return DriverNavigationHandoff.canOpen(.googleMaps)
                ? "Installed and ready for handoff."
                : "Not installed. Rydr will fall back to Apple Maps."
        case .waze:
            return DriverNavigationHandoff.canOpen(.waze)
                ? "Installed and ready for handoff."
                : "Not installed. Rydr will fall back to Apple Maps."
        }
    }

    var icon: String {
        switch self {
        case .rydr: return "location.north.line.fill"
        case .appleMaps: return "map.fill"
        case .googleMaps: return "g.circle.fill"
        case .waze: return "car.circle.fill"
        }
    }
}

enum DriverNavigationHandoff {
    static let preferenceKey = "driverDefaultNavigationProvider"

    static var currentProvider: DriverNavigationProvider {
        let rawValue = UserDefaults.standard.string(forKey: preferenceKey) ?? DriverNavigationProvider.rydr.rawValue
        return DriverNavigationProvider(rawValue: rawValue) ?? .rydr
    }

    static func canOpen(_ provider: DriverNavigationProvider) -> Bool {
        switch provider {
        case .rydr, .appleMaps:
            return true
        case .googleMaps:
            return UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        case .waze:
            return UIApplication.shared.canOpenURL(URL(string: "waze://")!)
        }
    }

    @discardableResult
    static func open(
        provider: DriverNavigationProvider,
        coordinate: CLLocationCoordinate2D,
        name: String?
    ) -> Bool {
        switch provider {
        case .rydr:
            return false
        case .appleMaps:
            openAppleMaps(coordinate: coordinate, name: name)
            return true
        case .googleMaps:
            guard openGoogleMaps(coordinate: coordinate) else {
                openAppleMaps(coordinate: coordinate, name: name)
                return true
            }
            return true
        case .waze:
            guard openWaze(coordinate: coordinate) else {
                openAppleMaps(coordinate: coordinate, name: name)
                return true
            }
            return true
        }
    }

    private static func openAppleMaps(coordinate: CLLocationCoordinate2D, name: String?) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private static func openGoogleMaps(coordinate: CLLocationCoordinate2D) -> Bool {
        guard let url = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving"),
              UIApplication.shared.canOpenURL(url)
        else { return false }
        UIApplication.shared.open(url)
        return true
    }

    private static func openWaze(coordinate: CLLocationCoordinate2D) -> Bool {
        guard let url = URL(string: "waze://?ll=\(coordinate.latitude),\(coordinate.longitude)&navigate=yes"),
              UIApplication.shared.canOpenURL(url)
        else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
