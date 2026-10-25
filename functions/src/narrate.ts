import { HttpsError, onCall } from "firebase-functions/v2/https";
import { ANTHROPIC_API_KEY, generateText } from "./ai";
import { callableOpts, canAccessBook, db, entitlementOf, requireUid } from "./core";

const PERSONAS: Record<string, string> = {
  storyteller:
    "a warm storyteller: vivid, unhurried, gently dramatic, using imagery and rhythm as if reading aloud by a fire",
  teacher:
    "a clear, encouraging teacher: structured, explains key ideas plainly, briefly signposts what matters and why",
  motivator:
    "an energising motivational speaker: confident, direct, uses short punchy sentences and calls to action",
};

const MAX_PASSAGE = 6000;

/**
 * Re-voices a passage of a book the user is entitled to, in the chosen
 * persona, for on-device text-to-speech. The output is spoken text only
 * (no markdown) and stays faithful to the source.
 */
export const narratePassage = onCall({ ...callableOpts, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120 }, async (req) => {
  const uid = requireUid(req);
  const { bookId, passage, persona } = req.data as { bookId?: string; passage?: string; persona?: string };
  if (!bookId || !passage || !persona || !PERSONAS[persona]) throw new HttpsError("invalid-argument", "bookId, passage and persona are required");
  if (passage.length > MAX_PASSAGE) throw new HttpsError("invalid-argument", "Passage too long");
  if (!canAccessBook(await entitlementOf(uid), bookId)) throw new HttpsError("permission-denied", "Subscription required");

  const book = await db.doc(`books/${bookId}`).get();
  const script = await generateText({
    system: `You narrate passages from "${book.get("title")}" by ${book.get("author")} as ${PERSONAS[persona]}.
Rules: keep every idea, fact and instruction from the passage and add none of your own; keep it
roughly the same length (at most 30% longer); output plain spoken prose only — no headings,
lists, markdown, stage directions or quotation marks around the whole text.`,
    prompt: passage,
  });
  return { script };
});
