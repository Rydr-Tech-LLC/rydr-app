export interface ActiveRideSummary {
  id: string;
  status: string;
  riderId?: string;
  driverId?: string;
  pickup?: string;
  dropoff?: string;
  updatedAtMillis?: number;
}
