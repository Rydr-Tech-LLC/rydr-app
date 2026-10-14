/** Build a Google Images search from the vehicle and optional color slot. */
export function vehicleImageSearchUrl(vehicle: {
  make?: string; model?: string; yearStart?: string | number; trim?: string | null;
}, color?: string): string {
  const query = [vehicle.yearStart, vehicle.make, vehicle.model, vehicle.trim, color, "vehicle white background"]
    .filter(value => value !== undefined && value !== null && String(value).trim())
    .map(value => String(value).trim()).join(" ");
  return `https://www.google.com/search?tbm=isch&q=${encodeURIComponent(query)}`;
}
