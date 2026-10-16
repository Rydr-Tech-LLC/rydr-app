import {currentWorkspace} from "../services/workspaceRuntime";
import {workspaceServiceURL} from "../services/workspacePolicy";
import fetch from "node-fetch";
import { defineSecret, defineString } from "firebase-functions/params";
import { onSchedule } from "../workspaceFunctions";

const internalToken = defineSecret("RYDR_INTERNAL_SERVICE_TOKEN");
const rydrBackendURL = defineString("RYDR_BACKEND_URL", {
  default: "https://rydr-backend.onrender.com"
});

export const maintainScheduledRides = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "America/New_York",
    retryCount: 3,
    secrets: [internalToken]
  },
  async () => {
    const response = await fetch(`${workspaceServiceURL(rydrBackendURL.value(),currentWorkspace())}/scheduled-rides/internal/sweep`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-rydr-internal-token": internalToken.value()
      },
      body: "{}"
    });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Scheduled ride sweep failed: HTTP ${response.status} ${body.slice(0, 300)}`);
    }
  }
);
