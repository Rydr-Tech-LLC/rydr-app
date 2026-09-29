const { findBestDrivers } = require('./driverMatchingService');

const mockRide = {
    rideType: "uberX",
    pickupLocation: { lat: 34.0522, lng: -118.2437 },
    tripLength: "short",
    destinationZone: "downtown"
};

const mockDrivers = [
    {
        driverId: "Driver_A_High_Rating",
        isOnline: true, 
        supportedRideTypes: ["UBERX"],
        currentLocation: { lat: 34.0522, lng: -118.2437 }, 
        maxPickupDistanceMiles: 5,
        rating: 4.9, // +20 points
        preferences: { tripLength: "long", destination: null } 
    },
    {
        driverId: "Driver_B_Perfect_Destination",
        isOnline: true, 
        supportedRideTypes: ["UBERX"],
        currentLocation: { lat: 34.0522, lng: -118.2437 }, 
        maxPickupDistanceMiles: 5,
        rating: 4.5, // 0 points
        preferences: { tripLength: "short", destination: "downtown" } // +15 and +30 points!
    }
];

test('findBestDrivers ranks strict matches over fallback matches', () => {
    const results = findBestDrivers(mockRide, mockDrivers);
    
    console.log("FINAL TEST RESULTS:", results);
    
    expect(results.length).toBe(2);
    // Driver B should win because 45 preference points > 20 rating points
    expect(results[0].driverId).toBe("Driver_B_Perfect_Destination");
    expect(results[0].score).toBe(45);
});