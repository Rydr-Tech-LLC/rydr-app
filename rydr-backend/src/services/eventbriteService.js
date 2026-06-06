const mockEvents = [
  {
    id: "1",
    title: "Atlanta Food Festival",
    city: "Atlanta"
  }
];

async function getEvents() {
  return mockEvents;
}

async function getEventById(id) {
  return mockEvents.find((event) => event.id === id) || null;
}

module.exports = {
  getEvents,
  getEventById
};
