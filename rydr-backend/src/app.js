require("dotenv").config();

const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");

const healthRoutes = require("./routes/health");
const eventRoutes = require("./routes/events");
const communityRoutes = require("./routes/community");
const chatRoutes = require("./routes/chat");
const notificationRoutes = require("./routes/notifications");
const driverRoutes = require("./routes/driver");
const moderationRoutes = require("./routes/moderation");

const app = express();
const port = process.env.PORT || 3000;

app.use(helmet());
const corsOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(",").map((origin) => origin.trim()).filter(Boolean)
  : true;

app.use(cors({ origin: corsOrigins }));
app.use(express.json());
app.use(morgan(process.env.NODE_ENV === "production" ? "combined" : "dev"));

app.use("/", healthRoutes);
app.use("/events", eventRoutes);
app.use("/community", communityRoutes);
app.use("/chat", chatRoutes);
app.use("/notifications", notificationRoutes);
app.use("/driver", driverRoutes);
app.use("/moderation", moderationRoutes);

app.use((req, res) => {
  res.status(404).json({
    error: "Not Found",
    message: `Route ${req.method} ${req.originalUrl} does not exist`
  });
});

app.use((err, req, res, next) => {
  const statusCode = err.statusCode || 500;

  if (process.env.NODE_ENV !== "test") {
    console.error(err);
  }

  const payload = {
    error: statusCode === 500 ? "Internal Server Error" : err.message,
    message: process.env.NODE_ENV === "production" ? undefined : err.message
  };

  if (err.details) {
    payload.details = err.details;
  }

  res.status(statusCode).json(payload);
});

if (require.main === module) {
  app.listen(port, () => {
    console.log(`rydr-backend listening on port ${port}`);
  });
}

module.exports = app;
