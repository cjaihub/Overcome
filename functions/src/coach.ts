import type Anthropic from "@anthropic-ai/sdk";
import { FieldPath } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { ANTHROPIC_API_KEY, generateStructured } from "./ai";
import { BRAND_GUIDE } from "./brand";
import { FieldValue, bucket, callableOpts, db, entitlementOf, hasPremium, requireUid } from "./core";

export const EMOTIONS = ["calm", "hopeful", "happy", "neutral", "stressed", "anxious", "sad", "frustrated", "tired", "craving"] as const;

export const coachSchema = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "emotion", "actions", "voiceStyle"],
  properties: {
    reply: { type: "string" },
    emotion: {
      type: "object",
      additionalProperties: false,
      required: ["label", "confidence", "cues"],
      properties: {
        label: { type: "string", enum: [...EMOTIONS] },
        confidence: { type: "number" },
        cues: { type: "string" },
      },
    },
    actions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "label", "target"],
        properties: {
          type: { type: "string", enum: ["route", "url"] },
          label: { type: "string" },
          target: { type: "string" },
        },
      },
    },
    voiceStyle: {
      type: "object",
      additionalProperties: false,
      required: ["rate", "pitch"],
      properties: { rate: { type: "number" }, pitch: { type: "number" } },
    },
  },
} as const;

interface CoachOutput {
  reply: string;
  emotion: { label: string; confidence: number; cues: string };
  actions: { type: "route" | "url"; label: string; target: string }[];
  voiceStyle: { rate: number; pitch: number };
}

const ROUTES = [/^\/form\/[a-z0-9_]+$/, /^\/book\/[\w-]+(\/(read|listen|narrator))?$/, /^\/(home|progress|library|settings|paywall|redeem)$/];

/** Keeps only safe, working actions: allowlisted app routes and https links. */
export function sanitizeActions(actions: CoachOutput["actions"]): CoachOutput["actions"] {
  return actions
    .filter((a) =>
      a.type === "route" ? ROUTES.some((r) => r.test(a.target)) : /^https:\/\/[^\s]+$/.test(a.target),
    )
    .map((a) => ({ ...a, label: a.label.slice(0, 40) }))
    .slice(0, 3);
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, Number.isFinite(v) ? v : lo));

const SYSTEM = `You are the Ovacome coach — a warm, sharp companion helping someone reduce compulsive
phone use and reinvest their attention. You see their profile, plan, live usage data and recent
check-ins in a <context> block; use specifics from it (numbers, apps, times) rather than generic advice.

${BRAND_GUIDE}

How to respond:
- Keep replies short for chat (2–5 sentences) unless they ask for detail. Plain text; you may include
  https links when genuinely useful.
- Estimate the user's emotion from their words and, for voice messages, the acoustic cues provided
  (fast speech and high loudness variation suggest agitation/stress; slow speech, low loudness and many
  pauses suggest tiredness or sadness). Report it in "emotion" with an honest confidence (0–1) and a
  short "cues" phrase. Adapt your tone to it: calmer and slower when stressed, gentle when sad, upbeat
  when hopeful. Never claim certainty about feelings.
- Offer up to 3 "actions" the user can tap: app routes (/form/<form id> for their check-in forms,
  /form/urge_log for urges, /book/<id> for a library book, /progress, /library, /home, /settings)
  or https links. Only use ids that appear in the context.
- voiceStyle: speech rate 0.35–0.65 (lower = slower, calmer) and pitch 0.85–1.15 for reading your
  reply aloud, matched to the moment.
- If they mention self-harm, suicide or being in danger: respond with care, encourage contacting local
  emergency services or a crisis line now, and include the action {"type":"url","label":"Find a helpline",
  "target":"https://findahelpline.com"}. You are not a therapist and never diagnose.`;

/**
 * The coach chat. Writes the user's message and the reply to
 * `users/{uid}/coach`, which the app streams in real time.
 */
export const coachReply = onCall(
  { ...callableOpts, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120, memory: "512MiB" },
  async (req) => {
    const uid = requireUid(req);
    const { text = "", imagePath, voice, assistantName = "Ova", localTime } = req.data as {
      text?: string; imagePath?: string; voice?: Record<string, number>; assistantName?: string; localTime?: string;
    };
    if (!text.trim() && !imagePath) throw new HttpsError("invalid-argument", "Say something first.");
    if (text.length > 4000) throw new HttpsError("invalid-argument", "Message too long.");
    if (imagePath && !imagePath.startsWith(`users/${uid}/chat/`)) throw new HttpsError("permission-denied", "Bad image path.");
    if (!hasPremium(await entitlementOf(uid))) throw new HttpsError("permission-denied", "The coach is part of Premium.");

    const userRef = db.doc(`users/${uid}`);
    const since = new Date(Date.now() - 8 * 86_400_000).toISOString().slice(0, 10).replace(/-/g, "");
    const [user, plan, usage, checkIns, history, books] = await Promise.all([
      userRef.get(),
      db.doc(`users/${uid}/plan/current`).get(),
      db.collection(`users/${uid}/usage`).where(FieldPath.documentId(), ">=", since).get(),
      db.collection(`users/${uid}/checkIns`).orderBy("at", "desc").limit(5).get(),
      db.collection(`users/${uid}/coach`).orderBy("clientAt", "desc").limit(16).get(),
      db.collection("books").where("published", "==", true).limit(20).get(),
    ]);

    const context = {
      localTime,
      assistantName,
      profile: user.get("profile") ?? {},
      plan: plan.exists ? { title: plan.get("title"), phases: plan.get("phases"), forms: (plan.get("forms") ?? []).map((f: { id: string; title: string }) => ({ id: f.id, title: f.title })) } : null,
      usageByDay: usage.docs.map((d) => ({ day: d.id, ...d.data(), updatedAt: undefined })),
      recentCheckIns: checkIns.docs.map((d) => ({ form: d.get("formId"), answers: d.get("answers"), at: d.get("at")?.toDate().toISOString() })),
      library: books.docs.map((d) => ({ id: d.id, title: d.get("title"), author: d.get("author"), category: d.get("category") })),
    };

    // Prior turns, oldest first, merged so roles alternate.
    const messages: Anthropic.Beta.Messages.BetaMessageParam[] = [];
    for (const d of history.docs.reverse()) {
      const role = d.get("role") === "assistant" ? "assistant" : "user";
      const content = String(d.get("text") ?? "") || "(shared a photo)";
      const last = messages[messages.length - 1];
      if (last?.role === role) last.content = `${last.content as string}\n${content}`;
      else messages.push({ role, content });
    }
    if (messages[0]?.role === "assistant") messages.shift();

    const content: Anthropic.Beta.Messages.BetaContentBlockParam[] = [];
    let imageUrl: string | null = null;
    if (imagePath) {
      const file = bucket().file(imagePath);
      const [[bytes], [meta]] = await Promise.all([file.download(), file.getMetadata()]);
      const type = String(meta.contentType ?? "image/jpeg");
      if (bytes.length > 5 * 1024 * 1024) throw new HttpsError("invalid-argument", "Image too large.");
      content.push({
        type: "image",
        source: { type: "base64", media_type: (["image/png", "image/webp", "image/gif"].includes(type) ? type : "image/jpeg") as "image/jpeg", data: bytes.toString("base64") },
      });
      [imageUrl] = await file.getSignedUrl({ version: "v4", action: "read", expires: Date.now() + 7 * 86_400_000 });
    }
    content.push({
      type: "text",
      text: `<context>${JSON.stringify(context)}</context>\n${voice ? `<voice_cues>${JSON.stringify(voice)}</voice_cues>\n` : ""}${text || "(photo only)"}`,
    });
    // Roles must alternate: fold into a trailing user turn rather than invent a reply.
    const last = messages[messages.length - 1];
    if (last?.role === "user") {
      last.content = [{ type: "text", text: last.content as string }, ...content];
    } else {
      messages.push({ role: "user", content });
    }

    const out = await generateStructured<CoachOutput>({ system: SYSTEM, messages, schema: coachSchema as unknown as Record<string, unknown> });

    const batch = db.batch();
    const coll = db.collection(`users/${uid}/coach`);
    const now = Date.now();
    batch.set(coll.doc(), {
      role: "user",
      text,
      imageUrl,
      voice: voice ?? null,
      at: FieldValue.serverTimestamp(),
      clientAt: now,
    });
    batch.set(coll.doc(), {
      role: "assistant",
      text: out.reply,
      emotion: { label: out.emotion.label, confidence: clamp(out.emotion.confidence, 0, 1), cues: out.emotion.cues.slice(0, 120) },
      actions: sanitizeActions(out.actions),
      voiceStyle: { rate: clamp(out.voiceStyle.rate, 0.35, 0.65), pitch: clamp(out.voiceStyle.pitch, 0.85, 1.15) },
      // Sort after the user's message even when both land in the same instant.
      at: FieldValue.serverTimestamp(),
      clientAt: now + 1,
    });
    await batch.commit();
    return { reply: out.reply, emotion: out.emotion.label };
  },
);
