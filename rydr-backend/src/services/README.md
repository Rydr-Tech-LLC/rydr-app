# Driver Matching Service

A standalone backend module that evaluates a list of driver candidates against a rider's request. It filters out ineligible drivers, applies preference-based scoring, and returns the top matches.

## 📥 Inputs

The `findBestDrivers(rideRequest, candidates)` function accepts two arguments:

**1. `rideRequest` (Object)**
*   `rideType`: The requested car tier (e.g., "uberX").
*   `pickupLocation`: GPS coordinates `{ lat, lng }`.
*   `tripLength`: Estimated length of the trip (e.g., "short", "long").
*   `destinationZone`: The destination neighborhood (e.g., "downtown").

**2. `candidates` (Array of Objects)**
*   A list of driver profiles containing their `isOnline` status, `supportedRideTypes`, `currentLocation`, `rating`, `maxPickupDistanceMiles`, and a `preferences` object (trip length and destination).

---

## ⚙️ Rules & Logic Pipeline

The matching algorithm processes candidates in four distinct steps:

### 1. Sanitization
*   Normalizes the incoming `rideType` (forces uppercase) to ensure database formatting matches front-end inputs.

### 2. Hard Filters (Eligibility)
Drivers are immediately excluded if they meet any of the following:
*   **Offline:** `driver.isOnline` is false.
*   **Incompatible:** The requested ride type is not in their `supportedRideTypes` array.
*   **Out of Range:** The calculated Haversine distance between the driver and the pickup location exceeds the driver's `maxPickupDistanceMiles`.

### 3. Preference Scoring
Eligible drivers start with `0` points and earn bonuses based on preferences:
*   **+20 Points:** Driver has a high rating (>= 4.8).
*   **+15 Points:** Driver's preferred `tripLength` matches the request, or is set to `"any"`.
*   **+30 Points:** Driver's preferred `destination` perfectly matches the requested `destinationZone`.

### 4. Ranking
*   Ranks strict matches (high scores) above fallback matches (lower scores).

---

## 📤 Output

Returns an array of up to **3** driver objects, sorted from highest score to lowest. 

**Example Output:**
```json
[
  {
    "driverId": "Driver_B_Perfect_Destination",
    "score": 45,
    "matchReason": "Perfect destination match"
  },
  {
    "driverId": "Driver_A_High_Rating",
    "score": 20,
    "matchReason": "Highly Rated Driver"
  }
]