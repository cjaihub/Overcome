import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { FieldValue, Timestamp, dayKey, db } from "./core";

/** Event types the app may log (anything else is ignored). */
export const EVENT_TYPES = new Set([
  "app_open", "session_end", "onboarding_step", "onboarding_complete", "plan_assigned", "form_submit",
  "book_view", "book_open", "pdf_page_view", "audio_play", "audio_complete", "read_along_start",
  "ai_narration", "paywall_view", "purchase", "code_redeemed", "capture_attempt",
]);

/**
 * Rolls every raw event up into:
 *  - `users/{uid}.stats`              per-user counters + last activity
 *  - `metrics/global`                 all-time totals
 *  - `metrics/global/daily/{yyyymmdd}` daily totals + distinct active users
 * The admin dashboard reads only these roll-ups.
 */
export const aggregateEvent = onDocumentCreated("users/{uid}/events/{eventId}", async (event) => {
  const { uid } = event.params;
  const type = event.data?.get("type") as string | undefined;
  if (!type || !EVENT_TYPES.has(type)) return;

  const day = dayKey();
  const inc = FieldValue.increment(1);
  const seconds = type === "session_end" ? Math.min(Number(event.data?.get("props.durationSec")) || 0, 6 * 3600) : 0;

  const batch = db.batch();
  batch.set(
    db.doc(`users/${uid}`),
    { stats: { [type]: inc, lastActiveAt: FieldValue.serverTimestamp(), ...(seconds ? { session_seconds: FieldValue.increment(seconds) } : {}) } },
    { merge: true },
  );
  batch.set(db.doc("metrics/global"), { [type]: inc }, { merge: true });
  batch.set(
    db.doc(`metrics/global/daily/${day}`),
    { [type]: inc, ...(seconds ? { session_seconds: FieldValue.increment(seconds) } : {}) },
    { merge: true },
  );
  await batch.commit();

  // Distinct daily active users: the marker doc can only be created once.
  try {
    await db.doc(`metrics/global/daily/${day}/active/${uid}`).create({ at: FieldValue.serverTimestamp() });
    await db.doc(`metrics/global/daily/${day}`).set({ activeUsers: inc }, { merge: true });
  } catch (e) {
    if ((e as { code?: number }).code !== 6) throw e; // 6 = ALREADY_EXISTS
  }
});

/** Nightly recount of subscribers and active trials for the dashboard. */
export const recountMetrics = onSchedule("every day 03:00", async () => {
  const now = Timestamp.now();
  const [subs, trials, users] = await Promise.all([
    db.collection("users").where("entitlement.premiumUntil", ">", now).count().get(),
    db.collection("users").where("entitlement.trialEndsAt", ">", now).count().get(),
    db.collection("users").count().get(),
  ]);
  await db.doc("metrics/global").set(
    { subscribers: subs.data().count, trials: trials.data().count, users: users.data().count, recountedAt: now },
    { merge: true },
  );
});

/** Hourly: push the daily check-in reminder to users whose local hour matches. */
export const dailyNudge = onSchedule("every 1 hours", async () => {
  const hour = new Date().getUTCHours();
  const q = await db
    .collection("users")
    .where("settings.reminders", "==", true)
    .where("settings.reminderUtcHour", "==", hour)
    .get();

  const messaging = getMessaging();
  for (const doc of q.docs) {
    const tokens = (doc.get("fcmTokens") as string[] | undefined) ?? [];
    if (!tokens.length) continue;
    const name = ((doc.get("profile.displayName") as string | undefined) ?? "").split(" ")[0];
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: name ? `${name}, how was today?` : "How was today?",
        body: "Take 60 seconds for your check-in. Small steps, every day.",
      },
      data: { route: "/home" },
      android: { notification: { channelId: "checkins" } },
    });
    const stale = res.responses.flatMap((r, i) =>
      !r.success && r.error?.code === "messaging/registration-token-not-registered" ? [tokens[i]] : [],
    );
    if (stale.length) await doc.ref.update({ fcmTokens: FieldValue.arrayRemove(...stale) });
  }
  logger.info(`dailyNudge: ${q.size} users at UTC hour ${hour}`);
});
