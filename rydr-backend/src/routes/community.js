const express = require("express");

const router = express.Router();

const mockPosts = [
  {
    id: "1",
    author: "Rydr Team",
    title: "Welcome to the Rydr community",
    body: "Community posts will live here."
  }
];

router.get("/posts", (req, res) => {
  res.json(mockPosts);
});

router.post("/posts", (req, res) => {
  res.status(201).json({
    id: "mock-post-id",
    status: "created",
    message: "Community post placeholder created",
    data: req.body || {}
  });
});

module.exports = router;
