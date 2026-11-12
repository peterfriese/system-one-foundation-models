import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";

// Initialize Firebase Admin SDK for token verification and consumption
initializeApp();

// Define the secret stored in Google Cloud Secret Manager
const typesafeApiKey = defineSecret("TYPESAFE_API_KEY");

/**
 * A Firebase Cloud Function (2nd Gen) reverse proxy that:
 * 1. Verifies Firebase App Check tokens (`X-Firebase-AppCheck`) via Firebase Admin SDK.
 * 2. Optionally consumes limited-use tokens for replay protection (when CONSUME_APP_CHECK="true").
 * 3. Validates incoming payload shape to prevent unauthorized traffic from reaching upstream.
 * 4. Injects the upstream TYPESAFE_API_KEY from Google Secret Manager.
 * 5. Forwards requests to TypeSafe AI's Jev System One evaluation endpoint with a timeout,
 *    preserving upstream Retry-After and timing headers without echoing internal error strings.
 */
export const systemone = onRequest(
  {
    cors: false,
    secrets: [typesafeApiKey],
    // Performance tuning:
    // minInstances: 1 keeps a container warm 24/7 to eliminate ~500ms-1.5s cold starts.
    // Omit or set to 0 for cost-optimized personal projects.
    minInstances: 1,
    // Concurrency allows up to 80 concurrent mobile requests per warm container
    concurrency: 80,
  },
  async (req, res) => {
    // Only POST requests are valid for Jev evaluations
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    // Verify App Check Token & Optional Limited-Use Token Replay Protection
    const appCheckToken = req.header("X-Firebase-AppCheck");
    if (!appCheckToken) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const consume = process.env.CONSUME_APP_CHECK === "true";
    try {
      const claims = await getAppCheck().verifyToken(appCheckToken, consume ? { consume: true } : undefined);
      if (consume && claims.alreadyConsumed) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
    } catch (error) {
      console.error("App Check token verification failed:", error);
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    // Validate request payload structure before forwarding to billable upstream
    const { state, questions } = req.body ?? {};
    if (
      !state ||
      typeof state !== "string" ||
      state.trim().length === 0 ||
      !questions ||
      typeof questions !== "object" ||
      Array.isArray(questions) ||
      Object.keys(questions).length === 0
    ) {
      res.status(400).json({ error: "Bad Request: Payload must include a non-empty 'state' string and a non-empty 'questions' object" });
      return;
    }

    try {
      const upstreamResponse = await fetch("https://api.typesafe.ai/v1/systemone", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${typesafeApiKey.value()}`,
        },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(15000), // 15-second upstream timeout
      });

      const responseText = await upstreamResponse.text();
      res.setHeader("Content-Type", upstreamResponse.headers.get("Content-Type") || "application/json");
      for (const headerName of ["Retry-After", "server-timing", "x-envoy-upstream-service-time"]) {
        const headerVal = upstreamResponse.headers.get(headerName);
        if (headerVal) {
          res.setHeader(headerName, headerVal);
        }
      }
      res.status(upstreamResponse.status).send(responseText);
    } catch (error) {
      console.error("Upstream System One proxy failure:", error);
      res.status(502).json({ error: "Upstream evaluation failed" });
    }
  }
);
