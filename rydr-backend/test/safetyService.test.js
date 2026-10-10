const test = require("node:test");
const assert = require("node:assert/strict");
const { createSafetyReport, listReportableRides } = require("../src/services/safetyService");

class FakeDocumentSnapshot {
  constructor(ref, value) {
    this.ref = ref;
    this.id = ref.path.split("/").at(-1);
    this.exists = value != null;
    this.value = value;
  }
  data() { return this.value; }
}

class FakeDocumentRef {
  constructor(db, path) { this.db = db; this.path = path; }
  get id() { return this.path.split("/").at(-1); }
  async get() { return new FakeDocumentSnapshot(this, this.db.values.get(this.path)); }
  async create(value) {
    if (this.db.values.has(this.path)) throw new Error("already exists");
    this.db.values.set(this.path, value);
  }
}

class FakeQuery {
  constructor(db, collectionPath, filters = [], ordering = null, max = Infinity) {
    this.db = db;
    this.collectionPath = collectionPath;
    this.filters = filters;
    this.ordering = ordering;
    this.max = max;
  }
  where(field, operator, value) {
    assert.equal(operator, "==");
    return new FakeQuery(this.db, this.collectionPath, [...this.filters, [field, value]], this.ordering, this.max);
  }
  orderBy(field, direction) {
    return new FakeQuery(this.db, this.collectionPath, this.filters, [field, direction], this.max);
  }
  limit(max) { return new FakeQuery(this.db, this.collectionPath, this.filters, this.ordering, max); }
  async get() {
    const prefix = `${this.collectionPath}/`;
    let docs = [...this.db.values.entries()]
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
      .map(([path, value]) => new FakeDocumentSnapshot(new FakeDocumentRef(this.db, path), value))
      .filter((doc) => this.filters.every(([field, value]) => doc.data()[field] === value));
    if (this.ordering) {
      const [field, direction] = this.ordering;
      const millis = (value) => value?.toMillis?.() ?? Number(value?.seconds || 0) * 1000;
      docs.sort((a, b) => (millis(a.data()[field]) - millis(b.data()[field])) * (direction === "desc" ? -1 : 1));
    }
    return { docs: docs.slice(0, this.max) };
  }
}

class FakeCollection extends FakeQuery {
  doc(id = `generated-${this.db.nextId++}`) { return new FakeDocumentRef(this.db, `${this.collectionPath}/${id}`); }
}

class FakeDb {
  constructor(values = {}) {
    this.values = new Map(Object.entries(values));
    this.nextId = 1;
  }
  collection(name) { return new FakeCollection(this, name); }
}

const timestamp = (seconds) => ({ seconds, toMillis: () => seconds * 1000 });

test("reportable rides only include the driver's completed rides in newest-first order", async () => {
  const db = new FakeDb({
    "rides/older": { driverId: "driver-1", riderName: "Alex", status: "completed", pickup: "A", dropoff: "B", rideType: "Rydr Go", completedAt: timestamp(100), updatedAt: timestamp(100) },
    "rides/newer": { driverId: "driver-1", riderName: "Sam", status: "completed", pickup: "C", dropoff: "D", rideType: "Rydr XL", completedAt: timestamp(200), updatedAt: timestamp(200) },
    "rides/active": { driverId: "driver-1", status: "inProgress", completedAt: timestamp(300), updatedAt: timestamp(300) },
    "rides/other-driver": { driverId: "driver-2", status: "completed", completedAt: timestamp(400), updatedAt: timestamp(400) }
  });

  const rides = await listReportableRides({ uid: "driver-1", db });

  assert.deepEqual(rides.map((ride) => ride.id), ["newer", "older"]);
  assert.equal(rides[0].riderName, "Sam");
  assert.equal(rides[0].completedAt, new Date(200_000).toISOString());
});

test("driver safety reports create a pending Mission Control investigation from backend ride evidence", async () => {
  const db = new FakeDb({
    "rides/ride-1": {
      driverId: "driver-1",
      driverName: "Jordan Driver",
      riderId: "rider-1",
      riderName: "Taylor Rider",
      status: "completed",
      rideType: "Rydr Go",
      pickup: "Pickup",
      dropoff: "Drop-off",
      completedAt: timestamp(500)
    }
  });

  const result = await createSafetyReport({
    uid: "driver-1",
    payload: { rideId: "ride-1", reportType: "rider_behavior", description: "The rider made a serious threat during the trip." },
    db
  });

  const report = db.values.get(`safetyReports/${result.reportId}`);
  assert.equal(report.reporterRole, "driver");
  assert.equal(report.reportedUserUid, "rider-1");
  assert.equal(report.riderName, "Taylor Rider");
  assert.equal(report.investigationStatus, "pending_review");
  assert.equal(report.missionControlQueue, "safety");
  assert.equal(report.status, "open");
});

test("a driver cannot report a ride they did not complete", async () => {
  const db = new FakeDb({
    "rides/ride-2": { driverId: "driver-2", riderId: "rider-2", status: "completed" }
  });

  await assert.rejects(
    createSafetyReport({ uid: "driver-1", payload: { rideId: "ride-2", description: "Enough incident detail to submit." }, db }),
    /Only ride participants/
  );
});
