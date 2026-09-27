/**
 * Takes a ride request and a list of driver candidates, 
 * then returns eligible drivers in ranked order.
 */
function findBestDrivers(rideRequest, candidates) {
    let eligibleDrivers = [];

    // Step 1: Normalizing data (like making rideType uppercase)
    if  (rideRequest == null || rideRequest.ridetype == null){
        console.log("Missing rideRequest or rideType")
        return [];
    }
    const normalizedRideType = rideRequest.rideType.toUpperCase();

    // Step 2: Filter out ineligible drivers (offline, wrong type, out of range, etc)
    const filteredDrivers = candidates.filter(driver => {
        // Rule 1: Online check
        if (driver.isOnline == false){
            return false;
        }
        // Rule 2: RideType check
        if (!driver.supportedRideTypes.includes(normalizedRideType)){
            return false;
        }
        // Rule 3: Distance check
        const distanceToRider = calculateDistance(
            rideRequest.pickupLocation.lat,
            rideRequest.pickupLocation.lng,
            driver.currentLocation.lat,
            driver.currentLocation.lng
        );

        if(distanceToRider > driver.maxPickupDistanceMiles){
            return false;
        }
         
        

        return true;
    });
    
    // Step 3: Score the remaining drivers
    const scoredDrivers = filteredDrivers.map(driver => {
        let score = 0;
        let matchReason = "Eligible match";

        //
        if (driver.rating >= 4.8 ){
            score += 20;
            matchReason = ("Highly Rated Driver");
        }

        return {
            driverId: driver.driverId,
            score: score,
            matchReason: matchReason
        };
    });
    
    // Step 4: Sort by highest score and return the top 3
    eligibleDrivers = scoredDrivers
        .sort((a, b) => b.score - a.score)
        .slice(0, 3);

    
    return eligibleDrivers;
}

// Helper function to calculate distance in miles between two coordinates
function calculateDistance(lat1, lon1, lat2, lon2){
    const R = 3958.8;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dlon = (lon2 - lon1) * (Math.PI / 180);
    const a = 
        Math.sin(dlat/2) * Math.sin(dLar/2) +
        Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) * Math.sin(dLon/2) * Math.sin(dlon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

// Export the function so your test file can see it
module.exports = {
    findBestDrivers
};