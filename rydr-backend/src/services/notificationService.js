async function getNotifications() {
  return [
    {
      id: "1",
      type: "system",
      title: "Rydr notifications ready",
      read: false
    }
  ];
}

module.exports = {
  getNotifications
};
