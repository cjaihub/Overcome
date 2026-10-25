import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { google } from "googleapis";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { logger } from "firebase-functions/v2";
import { FieldValue, Timestamp, callableOpts, db, requireUid } from "./core";

const ANDROID_PACKAGE = defineString("ANDROID_PACKAGE", { default: "com.overcome.overcome" });
const IOS_BUNDLE_ID = defineString("IOS_BUNDLE_ID", { default: "com.overcome.overcome" });
const IOS_APP_ID = defineString("IOS_APP_ID", { default: "" });
const APPLE_ENV = defineString("APPLE_ENV", { default: "Production" });

export const SUBSCRIPTIONS: Record<string, string> = {
  overcome_premium_monthly: "Monthly",
  overcome_premium_yearly: "Yearly",
};

const sha = (s: string) => createHash("sha256").update(s).digest("hex");

// ---------- Google Play ----------

const play = () =>
  google.androidpublisher({
    version: "v3",
    auth: new google.auth.GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] }),
  });

interface Verified {
  kind: "subscription" | "book";
  productId: string;
  expiresAt?: number;
  /** Stable id used to map store notifications back to the user. */
  storeKey: string;
}

async function verifyAndroid(productId: string, token: string): Promise<Verified> {
  const api = play();
  const packageName = ANDROID_PACKAGE.value();
  if (SUBSCRIPTIONS[productId]) {
    const { data } = await api.purchases.subscriptionsv2.get({ packageName, token });
    const active = ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"].includes(data.subscriptionState ?? "");
    const expiry = Math.max(...(data.lineItems ?? []).map((l) => Date.parse(l.expiryTime ?? "") || 0));
    if (!active) throw new HttpsError("failed-precondition", "Subscription is not active.");
    if (data.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
      await api.purchases.subscriptions.acknowledge({ packageName, subscriptionId: productId, token });
    }
    return { kind: "subscription", productId, expiresAt: expiry, storeKey: `play:${sha(token)}` };
  }
  const { data } = await api.purchases.products.get({ packageName, productId, token });
  if (data.purchaseState !== 0) throw new HttpsError("failed-precondition", "Purchase is not complete.");
  if (data.acknowledgementState !== 1) {
    await api.purchases.products.acknowledge({ packageName, productId, token });
  }
  return { kind: "book", productId, storeKey: `play:${sha(token)}` };
}

// ---------- App Store (StoreKit 2 signed transactions) ----------

let verifier: SignedDataVerifier | undefined;
function appleVerifier(): SignedDataVerifier {
  if (verifier) return verifier;
  // Apple root certificates (AppleRootCA-G3.cer etc.) from
  // https://www.apple.com/certificateauthority/ placed in functions/certs.
  const dir = join(__dirname, "..", "..", "certs");
  const certs = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".cer")).map((f) => readFileSync(join(dir, f))) : [];
  if (!certs.length) throw new HttpsError("failed-precondition", "Apple root certificates are not configured.");
  const env = APPLE_ENV.value() === "Sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
  const appId = IOS_APP_ID.value() ? Number(IOS_APP_ID.value()) : undefined;
  verifier = new SignedDataVerifier(certs, true, env, IOS_BUNDLE_ID.value(), appId);
  return verifier;
}

async function verifyIos(productId: string, jws: string): Promise<Verified> {
  const tx = await appleVerifier().verifyAndDecodeTransaction(jws);
  if (tx.productId !== productId) throw new HttpsError("invalid-argument", "Product mismatch.");
  if (tx.revocationDate) throw new HttpsError("failed-precondition", "Purchase was refunded.");
  const storeKey = `apple:${tx.originalTransactionId}`;
  if (SUBSCRIPTIONS[productId]) {
    if (!tx.expiresDate || tx.expiresDate < Date.now()) throw new HttpsError("failed-precondition", "Subscription expired.");
    return { kind: "subscription", productId, expiresAt: tx.expiresDate, storeKey };
  }
  return { kind: "book", productId, storeKey };
}

// ---------- Entitlement writes ----------

async function bookIdForProduct(productId: string): Promise<string> {
  const q = await db.collection("books").where("productId", "==", productId).limit(1).get();
  if (q.empty) throw new HttpsError("not-found", "Unknown product.");
  return q.docs[0].id;
}

async function grant(uid: string, v: Verified): Promise<void> {
  const keyRef = db.doc(`storePurchases/${sha(v.storeKey)}`);
  const userRef = db.doc(`users/${uid}`);
  const bookId = v.kind === "book" ? await bookIdForProduct(v.productId) : undefined;

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(keyRef);
    // One store purchase can only ever unlock one account.
    if (existing.exists && existing.get("uid") !== uid) {
      throw new HttpsError("already-exists", "This purchase belongs to another account.");
    }
    tx.set(keyRef, { uid, productId: v.productId, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (v.kind === "subscription") {
      tx.update(userRef, {
        "entitlement.premiumUntil": Timestamp.fromMillis(v.expiresAt!),
        "entitlement.plan": SUBSCRIPTIONS[v.productId],
      });
    } else {
      tx.update(userRef, { "entitlement.ownedBooks": FieldValue.arrayUnion(bookId) });
    }
  });
}

/** Called by the app after every purchase or restore. */
export const verifyPurchase = onCall(callableOpts, async (req) => {
  const uid = requireUid(req);
  const { platform, productId, token } = req.data as { platform?: string; productId?: string; token?: string };
  if (!productId || !token) throw new HttpsError("invalid-argument", "productId and token are required");
  const verified = platform === "ios" ? await verifyIos(productId, token) : await verifyAndroid(productId, token);
  await grant(uid, verified);
  return { ok: true, kind: verified.kind };
});

/**
 * Google Play Real-time Developer Notifications (Pub/Sub topic
 * `play-billing`): keeps renewals, cancellations and refunds in sync.
 */
export const playBillingNotifications = onMessagePublished("play-billing", async (event) => {
  const msg = event.data.message.json as {
    subscriptionNotification?: { purchaseToken: string; subscriptionId: string };
  };
  const n = msg.subscriptionNotification;
  if (!n) return;
  const owner = await db.doc(`storePurchases/${sha(`play:${sha(n.purchaseToken)}`)}`).get();
  if (!owner.exists) return logger.warn("RTDN for unknown token");
  const { data } = await play().purchases.subscriptionsv2.get({ packageName: ANDROID_PACKAGE.value(), token: n.purchaseToken });
  const expiry = Math.max(...(data.lineItems ?? []).map((l) => Date.parse(l.expiryTime ?? "") || 0));
  await db.doc(`users/${owner.get("uid")}`).update({ "entitlement.premiumUntil": Timestamp.fromMillis(expiry) });
});

/** App Store Server Notifications V2 endpoint (configure in App Store Connect). */
export const appStoreNotifications = onRequest(async (req, res) => {
  try {
    const payload = await appleVerifier().verifyAndDecodeNotification(req.body.signedPayload);
    const signed = payload.data?.signedTransactionInfo;
    if (signed) {
      const tx = await appleVerifier().verifyAndDecodeTransaction(signed);
      const owner = await db.doc(`storePurchases/${sha(`apple:${tx.originalTransactionId}`)}`).get();
      if (owner.exists && tx.productId && SUBSCRIPTIONS[tx.productId]) {
        const until = tx.revocationDate ? Date.now() : (tx.expiresDate ?? Date.now());
        await db.doc(`users/${owner.get("uid")}`).update({ "entitlement.premiumUntil": Timestamp.fromMillis(until) });
      }
    }
    res.sendStatus(200);
  } catch (e) {
    logger.error("App Store notification rejected", e);
    res.sendStatus(400);
  }
});
