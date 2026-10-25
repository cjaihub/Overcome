import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { HttpsError } from "firebase-functions/v2/https";

export const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
export const MODEL = "claude-opus-5-5";

let client: Anthropic | undefined;
const claude = () => (client ??= new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() }));

/**
 * One Claude call that must return JSON matching [schema]. Uses structured
 * outputs so the response is guaranteed to parse, and server-side refusal
 * fallbacks so a policy decline is retried on the default fallback model.
 */
export async function generateJson<T>(opts: {
  system: string;
  prompt: string;
  schema: Record<string, unknown>;
  effort?: "low" | "medium" | "high";
  maxTokens?: number;
}): Promise<T> {
  const res = await claude().beta.messages.create({
    model: MODEL,
    max_tokens: opts.maxTokens ?? 16000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: opts.system,
    messages: [{ role: "user", content: opts.prompt }],
    output_config: {
      effort: opts.effort ?? "medium",
      format: { type: "json_schema", schema: opts.schema },
    },
  });
  if (res.stop_reason === "refusal") throw new HttpsError("failed-precondition", "The AI declined this request.");
  if (res.stop_reason === "max_tokens") throw new HttpsError("resource-exhausted", "The AI response was cut off.");
  const text = res.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  return JSON.parse(text) as T;
}

/** Structured output over a full conversation (used by the coach chat). */
export async function generateStructured<T>(opts: {
  system: string;
  messages: Anthropic.Beta.Messages.BetaMessageParam[];
  schema: Record<string, unknown>;
  effort?: "low" | "medium" | "high";
}): Promise<T> {
  const res = await claude().beta.messages.create({
    model: MODEL,
    max_tokens: 8000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: opts.system,
    messages: opts.messages,
    output_config: { effort: opts.effort ?? "medium", format: { type: "json_schema", schema: opts.schema } },
  });
  if (res.stop_reason === "refusal") throw new HttpsError("failed-precondition", "The AI declined this message.");
  if (res.stop_reason === "max_tokens") throw new HttpsError("resource-exhausted", "The AI response was cut off.");
  return JSON.parse(res.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("")) as T;
}

/** Plain-text generation (used by the narrator). */
export async function generateText(opts: { system: string; prompt: string; effort?: "low" | "medium" }): Promise<string> {
  const res = await claude().beta.messages.create({
    model: MODEL,
    max_tokens: 8000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: opts.system,
    messages: [{ role: "user", content: opts.prompt }],
    output_config: { effort: opts.effort ?? "low" },
  });
  if (res.stop_reason === "refusal") throw new HttpsError("failed-precondition", "The AI declined this passage.");
  return res.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("").trim();
}
