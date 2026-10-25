import { createHash, randomInt } from "node:crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, callableOpts, db, requireAdmin, requireUid } from "./core";

/** Unambiguous alphabet (no 0/O, 1/I/L). */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export const normalizeCode = (code: string) => code.toUpperCase().replace(/[^A-Z0-9]/g, "");
export const hashCode = (code: string) => createHash("sha256").update(`code:${normalizeCode(code)}`).digest("hex");

export function generateCode(): string {
  const raw = Array.from({ length: 12 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
  return raw.match(/.{4}/g)!.join("-");
}

interface AccessCode {
  premiumDays?: number;
  bookIds?: string[];
  phone?: string;
  expiresAt?: Timestamp;
  redeemedBy?: string;
}

/**
 * Redeems a one-time unlock code (shipped inside a purchased book, or issued
 * by a counselor). Only the hash is stored, codes are single-use, and a code
 * may be bound to one phone number.
 */
export const redeemAccessCode = onCall(callableOpts, async (req) => {
  const uid = requireUid(req);
  const code = String((req.data as { code?: string })?.code ?? "");
  if (normalizeCode(code).length < 8) throw new HttpsError("invalid-argument", "Enter a valid code.");

  const phone = req.auth?.token.phone_number as string | undefined;
  const codeRef = db.doc(`accessCodes/${hashCode(code)}`);
  const userRef = db.doc(`users/${uid}`);

  return db.runTransaction(async (tx) => {
    const [codeSnap, userSnap] = await Promise.all([tx.get(codeRef), tx.get(userRef)]);
    const c = codeSnap.data() as AccessCode | undefined;
    if (!c) throw new HttpsError("not-found", "That code doesn't exist.");
    if (c.redeemedBy) throw new HttpsError("already-exists", "That code has already been used.");
    if (c.expiresAt && c.expiresAt.toMillis() < Date.now()) throw new HttpsError("deadline-exceeded", "That code has expired.");
    if (c.phone && c.phone !== phone) throw new HttpsError("permission-denied", "That code is registered to another phone number.");

    const ent = (userSnap.get("entitlement") ?? {}) as { premiumUntil?: Timestamp };
    const update: Record<string, unknown> = {};
    const parts: string[] = [];
    if (c.premiumDays) {
      const base = Math.max(Date.now(), ent.premiumUntil?.toMillis() ?? 0);
      update["entitlement.premiumUntil"] = Timestamp.fromMillis(base + c.premiumDays * 86_400_000);
      update["entitlement.plan"] = "code";
      parts.push(`${c.premiumDays} days of Premium`);
    }
    if (c.bookIds?.length) {
      update["entitlement.ownedBooks"] = FieldValue.arrayUnion(...c.bookIds);
      parts.push(c.bookIds.length === 1 ? "your book" : `${c.bookIds.length} books`);
    }
    tx.update(userRef, update);
    tx.update(codeRef, { redeemedBy: uid, redeemedAt: FieldValue.serverTimestamp() });
    return { message: `Unlocked ${parts.join(" and ")}.` };
  });
});

/** Admin: mint a batch of codes. Returns plaintext once; only hashes are stored. */
export const createAccessCodes = onCall(callableOpts, async (req) => {
  const adminUid = requireAdmin(req);
  const { count = 1, premiumDays, bookIds, phone, expiresInDays } = req.data as {
    count?: number; premiumDays?: number; bookIds?: string[]; phone?: string; expiresInDays?: number;
  };
  if (count < 1 || count > 500) throw new HttpsError("invalid-argument", "count must be 1–500");
  if (!premiumDays && !bookIds?.length) throw new HttpsError("invalid-argument", "Grant premiumDays and/or bookIds");

  const codes: string[] = [];
  const batch = db.batch();
  for (let i = 0; i < count; i++) {
    const code = generateCode();
    codes.push(code);
    batch.set(db.doc(`accessCodes/${hashCode(code)}`), {
      premiumDays: premiumDays ?? null,
      bookIds: bookIds ?? [],
      phone: phone ?? null,
      expiresAt: expiresInDays ? Timestamp.fromMillis(Date.now() + expiresInDays * 86_400_000) : null,
      createdBy: adminUid,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return { codes };
});
