/**
 * Publishes a protected book.
 *
 *   npm run encrypt-book -- --id quiet-mind --pdf ./quiet-mind.pdf \
 *     [--transcript ./transcript.json] [--audio "Chapter 1=./ch1.m4a" ...] \
 *     --title "The Quiet Mind" --author "Jane Doe" [--product quiet_mind_book]
 *
 * - Generates a random AES-256 key per book, stored in `bookSecrets/{id}`
 *   (unreadable by clients).
 * - Encrypts the PDF and transcript as [12-byte nonce][ciphertext][16-byte tag]
 *   — the format `LibraryRepository.decryptFrom` expects.
 * - Uploads to Storage under `books/{id}/`, where client reads are denied;
 *   the app only ever gets 10-minute signed URLs via `getBookAccess`.
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS for a service account with
 * Firestore + Storage admin rights.
 */
import { createCipheriv, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import { parseArgs } from "node:util";
import { FieldValue, bucket, db } from "../src/core";

export function encrypt(plain: Buffer, key: Buffer): Buffer {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  const body = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([nonce, body, cipher.getAuthTag()]);
}

async function main() {
  const { values } = parseArgs({
    options: {
      id: { type: "string" },
      pdf: { type: "string" },
      transcript: { type: "string" },
      audio: { type: "string", multiple: true },
      title: { type: "string" },
      author: { type: "string" },
      description: { type: "string", default: "" },
      category: { type: "string", default: "Recovery" },
      accent: { type: "string", default: "aurora" },
      cover: { type: "string" },
      product: { type: "string" },
      featured: { type: "boolean", default: false },
      order: { type: "string", default: "100" },
    },
  });
  const id = values.id;
  if (!id || !values.title || !values.author) throw new Error("--id, --title and --author are required");

  const existing = await db.doc(`bookSecrets/${id}`).get();
  const key = existing.exists ? Buffer.from(existing.get("key"), "base64") : randomBytes(32);
  const b = bucket();
  const upload = async (path: string, data: Buffer, contentType: string) => {
    await b.file(path).save(data, { contentType, resumable: false, metadata: { cacheControl: "private, no-store" } });
    console.log(`uploaded ${path} (${data.length} bytes)`);
    return path;
  };

  const pdfPath = values.pdf
    ? await upload(`books/${id}/book.pdf.enc`, encrypt(readFileSync(values.pdf), key), "application/octet-stream")
    : undefined;
  const transcriptPath = values.transcript
    ? await upload(`books/${id}/transcript.json.enc`, encrypt(readFileSync(values.transcript), key), "application/octet-stream")
    : undefined;

  const chapters: { title: string; path: string }[] = [];
  for (const [i, spec] of (values.audio ?? []).entries()) {
    const [title, file] = spec.includes("=") ? spec.split("=") : [`Chapter ${i + 1}`, spec];
    const path = await upload(`books/${id}/audio/${String(i).padStart(3, "0")}${extname(file)}`, readFileSync(file), "audio/mp4");
    chapters.push({ title, path });
  }

  let coverUrl = "";
  if (values.cover) {
    const path = `covers/${id}${extname(values.cover)}`;
    await b.file(path).save(readFileSync(values.cover), { contentType: "image/jpeg", resumable: false });
    await b.file(path).makePublic();
    coverUrl = b.file(path).publicUrl();
  }

  await db.doc(`bookSecrets/${id}`).set({ key: key.toString("base64"), updatedAt: FieldValue.serverTimestamp() });
  await db.doc(`books/${id}`).set(
    {
      title: values.title,
      author: values.author,
      description: values.description,
      category: values.category,
      accent: values.accent,
      coverUrl,
      hasPdf: !!pdfPath,
      hasAudio: chapters.length > 0,
      pdfPath: pdfPath ?? null,
      transcriptPath: transcriptPath ?? null,
      chapters,
      productId: values.product ?? null,
      featured: values.featured,
      order: Number(values.order),
      published: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`Published ${id} (${basename(values.pdf ?? "no pdf")})`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
