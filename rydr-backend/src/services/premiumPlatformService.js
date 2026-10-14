async function requireExecutiveEnabled(db, rideType) {
  if (!String(rideType).toLowerCase().includes('executive')) return;
  const config = await db.collection('platformConfig').doc('rydrExecutive').get();
  if (!config.exists || config.data()?.enabled !== true || config.data()?.betaPaused === true || config.data()?.fundingApproved !== true) {
    const error = new Error('Rydr Executive is not open for bookings');
    error.statusCode = 409;
    throw error;
  }
}
module.exports = { requireExecutiveEnabled };
