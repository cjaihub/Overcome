import { createHash } from "node:crypto";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, auth, callableOpts, db, requireAdmin, requireUid } from "./core";

const TRIAL_DAYS = 7;

/** Comma-separated E.164 numbers that receive the `admin` claim on sign-in. */
const ADMIN_PHONES = defineString("ADMIN_PHONES", { default: "" });

const phoneHash = (phone: string) => createHash("sha256").update(`overcome:${phone}`).digest("hex");

/**
 * Idempotent first-run setup after phone sign-in:
 *  - creates the user document,
 *  - grants the 7-day free trial once per phone number (re-installs or new
 *    accounts on the same number don't get another trial),
 *  - promotes configured owner numbers to admin.
 */
export const bootstrapUser = onCall(callableOpts, async (req) => {
  const uid = requireUid(req);
  const phone = (req.auth?.token.phone_number as string | undefined) ?? "";
  if (!phone) throw new HttpsError("failed-precondition", "A verified phone number is required.");

  const userRef = db.doc(`users/${uid}`);
  const registryRef = db.doc(`trialRegistry/${phoneHash(phone)}`);

  const created = await db.runTransaction(async (tx) => {
    const [user, registry] = await Promise.all([tx.get(userRef), tx.get(registryRef)]);
    // The app may already have written e.g. its push token, so "set up" is
    // marked by createdAt rather than by the document existing.
    if (user.get("createdAt")) return false;

    const entitlement: Record<string, unknown> = { ownedBooks: [] };
    if (!registry.exists) {
      entitlement.trialEndsAt = Timestamp.fromMillis(Date.now() + TRIAL_DAYS * 86_400_000);
      tx.set(registryRef, { uid, at: FieldValue.serverTimestamp() });
    }
    tx.set(userRef, {
      phone,
      createdAt: FieldValue.serverTimestamp(),
      entitlement,
      stats: { lastActiveAt: FieldValue.serverTimestamp() },
    }, { merge: true });
    tx.set(db.doc("metrics/global"), { users: FieldValue.increment(1) }, { merge: true });
    return true;
  });

  const admins = ADMIN_PHONES.value().split(",").map((s) => s.trim()).filter(Boolean);
  if (admins.includes(phone) && req.auth?.token.admin !== true) {
    await auth.setCustomUserClaims(uid, { admin: true });
  }
  return { created };
});

/** Grants or revokes admin for another user (admins only). */
export const setAdmin = onCall(callableOpts, async (req) => {
  requireAdmin(req);
  const { uid, admin } = req.data as { uid?: string; admin?: boolean };
  if (!uid) throw new HttpsError("invalid-argument", "uid is required");
  await auth.setCustomUserClaims(uid, admin ? { admin: true } : {});
  return { ok: true };
});

/** Store-compliant account deletion: all user data, then the auth record. */
export const deleteAccount = onCall(callableOpts, async (req) => {
  const uid = requireUid(req);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.doc("metrics/global").set({ users: FieldValue.increment(-1) }, { merge: true });
  await auth.deleteUser(uid);
  return { ok: true };
});
