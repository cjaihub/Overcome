import { test } from "node:test";
import assert from "node:assert/strict";
import { createDecipheriv, randomBytes } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";
import { canAccessBook, hasPremium } from "./core";
import { generateCode, hashCode, normalizeCode } from "./codes";
import { parsePlan, personalise, planJsonSchema, signatureOf } from "./plan";
import { encrypt } from "../scripts/encrypt-book";

const future = Timestamp.fromMillis(Date.now() + 86_400_000);
const past = Timestamp.fromMillis(Date.now() - 86_400_000);

test("entitlement: trial or subscription grants premium; owned books always", () => {
  assert.equal(hasPremium({ trialEndsAt: future }), true);
  assert.equal(hasPremium({ trialEndsAt: past, premiumUntil: past }), false);
  assert.equal(canAccessBook({ trialEndsAt: past, ownedBooks: ["b1"] }, "b1"), true);
  assert.equal(canAccessBook({ trialEndsAt: past, ownedBooks: ["b1"] }, "b2"), false);
  assert.equal(canAccessBook(undefined, "b1"), false);
});

test("access codes: formatted, normalised and hashed consistently", () => {
  const code = generateCode();
  assert.match(code, /^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  assert.equal(normalizeCode(" abcd-efgh-jkmn "), "ABCDEFGHJKMN");
  assert.equal(hashCode(code.toLowerCase()), hashCode(code.replace(/-/g, "")));
});

test("signature groups users by primary habit, band and coach", () => {
  assert.equal(signatureOf({ habits: ["Short videos", "Gaming"], severityBand: "high", coachStyle: "motivator" }), "short_videos|high|motivator");
  assert.equal(signatureOf({}), "general|moderate|teacher");
});

const validPlan = () => ({
  title: "Plan",
  summary: "For {name}",
  icon: "target",
  accent: "aurora",
  phases: [1, 2, 3].map((i) => ({ title: `P${i}`, weeks: 2, focus: "f", actions: ["a", "b"] })),
  forms: [1, 2].map((i) => ({
    id: `form_${i}`, title: "F", description: "d", icon: "sun", accent: "iris", frequency: "daily",
    fields: [1, 2].map((j) => ({ id: `q_${j}`, label: "L", type: "scale", options: [], min: 0, max: 10, hint: "", required: true })),
  })),
  affirmations: ["1", "2", "3", "4", "5"],
});

test("parsePlan trims over-long strings and arrays instead of failing", () => {
  const raw = validPlan();
  raw.title = "x".repeat(80);
  raw.affirmations = Array.from({ length: 14 }, (_, i) => `a${i}`);
  const plan = parsePlan(raw);
  assert.equal(plan.title.length, 40);
  assert.equal(plan.affirmations.length, 10);
});

test("parsePlan rejects off-brand tokens", () => {
  const raw = validPlan();
  raw.accent = "neon-green";
  assert.throws(() => parsePlan(raw));
});

test("personalise fills placeholders and leads with the user's identity", () => {
  const plan = personalise(parsePlan(validPlan()), { displayName: "Ada Lovelace", identity: "I am present." });
  assert.equal(plan.summary, "For Ada");
  assert.equal(plan.affirmations[0], "I am present.");
});

test("structured-output schema only uses supported keywords and closes objects", () => {
  const banned = ["minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "pattern", "$schema"];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) return n.forEach(walk);
    if (!n || typeof n !== "object") return;
    const o = n as Record<string, unknown>;
    for (const b of banned) assert.ok(!(b in o), `found ${b}`);
    if (o.type === "object") assert.equal(o.additionalProperties, false);
    Object.values(o).forEach(walk);
  };
  walk(planJsonSchema);
});

test("book encryption matches the app's [nonce][ciphertext][tag] layout", () => {
  const key = randomBytes(32);
  const plain = Buffer.from("%PDF-1.7 protected content");
  const blob = encrypt(plain, key);
  const d = createDecipheriv("aes-256-gcm", key, blob.subarray(0, 12));
  d.setAuthTag(blob.subarray(blob.length - 16));
  assert.deepEqual(Buffer.concat([d.update(blob.subarray(12, blob.length - 16)), d.final()]), plain);
});

import { coachSchema, sanitizeActions } from "./coach";

test("coach actions: only allowlisted routes and https links survive", () => {
  const out = sanitizeActions([
    { type: "route", label: "Log urge", target: "/form/urge_log" },
    { type: "route", label: "Admin", target: "/admin" },
    { type: "url", label: "Helpline", target: "https://findahelpline.com" },
    { type: "url", label: "Bad", target: "javascript:alert(1)" },
    { type: "route", label: "Book", target: "/book/quiet-mind/listen" },
  ]);
  assert.deepEqual(out.map((a) => a.target), ["/form/urge_log", "https://findahelpline.com", "/book/quiet-mind/listen"]);
});

test("coach schema is valid for structured outputs (closed objects, all fields required)", () => {
  const walk = (n: any): void => {
    if (!n || typeof n !== "object") return;
    if (n.type === "object") {
      assert.equal(n.additionalProperties, false);
      assert.deepEqual([...n.required].sort(), Object.keys(n.properties).sort());
    }
    Object.values(n).forEach(walk);
  };
  walk(coachSchema);
});
