import { HttpsError, onCall } from "firebase-functions/v2/https";
import { bucket, callableOpts, canAccessBook, db, entitlementOf, requireUid } from "./core";

const URL_TTL_MS = 10 * 60 * 1000;

interface BookDoc {
  published?: boolean;
  pdfPath?: string;
  transcriptPath?: string;
  chapters?: { title: string; path: string }[];
}

async function signedUrl(path: string): Promise<string> {
  const [url] = await bucket().file(path).getSignedUrl({ version: "v4", action: "read", expires: Date.now() + URL_TTL_MS });
  return url;
}

/**
 * Issues a short-lived access grant for an entitled user:
 *  - the AES-256-GCM key for the encrypted PDF and transcript,
 *  - 10-minute signed URLs (Storage rules deny all direct client reads).
 * Keys live in `bookSecrets`, which no client can read.
 */
export const getBookAccess = onCall(callableOpts, async (req) => {
  const uid = requireUid(req);
  const bookId = String((req.data as { bookId?: string })?.bookId ?? "");
  if (!bookId) throw new HttpsError("invalid-argument", "bookId is required");

  const [bookSnap, secretSnap, ent] = await Promise.all([
    db.doc(`books/${bookId}`).get(),
    db.doc(`bookSecrets/${bookId}`).get(),
    entitlementOf(uid),
  ]);
  const book = bookSnap.data() as BookDoc | undefined;
  if (!book?.published) throw new HttpsError("not-found", "Book not found");
  if (!canAccessBook(ent, bookId)) throw new HttpsError("permission-denied", "Subscription or purchase required");

  const [pdfUrl, transcriptUrl, chapters] = await Promise.all([
    book.pdfPath ? signedUrl(book.pdfPath) : Promise.resolve(null),
    book.transcriptPath ? signedUrl(book.transcriptPath) : Promise.resolve(null),
    Promise.all((book.chapters ?? []).map(async (c) => ({ title: c.title, url: await signedUrl(c.path) }))),
  ]);

  return { key: secretSnap.get("key") as string, pdfUrl, transcriptUrl, chapters };
});
