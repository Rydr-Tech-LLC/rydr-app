const express = require("express");

const router = express.Router();

router.get("/conversations", (req, res) => {
  res.json([
    {
      id: "1",
      participants: ["user_1", "user_2"],
      lastMessage: "Chat foundation is ready."
    }
  ]);
});

router.post("/message", (req, res) => {
  res.status(201).json({
    id: "mock-message-id",
    status: "sent",
    message: "Chat message placeholder accepted",
    data: req.body || {}
  });
});

module.exports = router;
