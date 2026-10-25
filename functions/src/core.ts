import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 20 });

export const db = getFirestore();
export const auth = getAuth();
export const bucket = () => getStorage().bucket();
export { FieldValue, Timestamp };

/** Every callable requires a signed-in user and a valid App Check token. */
export const callableOpts = { enforceAppCheck: true, consumeAppCheckToken: false } as const;

export function requireUid(req: CallableRequest<unknown>): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  return req.auth.uid;
}

export function requireAdmin(req: CallableRequest<unknown>): string {
  const uid = requireUid(req);
  if (req.auth?.token.admin !== true) throw new HttpsError("permission-denied", "Admins only.");
  return uid;
}

export interface Entitlement {
  trialEndsAt?: Timestamp;
  premiumUntil?: Timestamp;
  plan?: string;
  ownedBooks?: string[];
}

export function hasPremium(e: Entitlement | undefined, now = Date.now()): boolean {
  if (!e) return false;
  return (e.trialEndsAt?.toMillis() ?? 0) > now || (e.premiumUntil?.toMillis() ?? 0) > now;
}

export function canAccessBook(e: Entitlement | undefined, bookId: string, now = Date.now()): boolean {
  return hasPremium(e, now) || (e?.ownedBooks ?? []).includes(bookId);
}

export async function entitlementOf(uid: string): Promise<Entitlement | undefined> {
  const snap = await db.doc(`users/${uid}`).get();
  return snap.get("entitlement") as Entitlement | undefined;
}

export const dayKey = (d = new Date()) => d.toISOString().slice(0, 10).replace(/-/g, "");
