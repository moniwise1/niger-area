// Paystack webhook. Credits coins only when:
//   1. the x-paystack-signature HMAC-SHA512 matches our secret key, and
//   2. Paystack's own verify endpoint confirms the charge succeeded for the same amount.
// credit_purchase() is idempotent, so Paystack's retries never double-credit.
// Deploy with --no-verify-jwt: Paystack does not send a Supabase JWT.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SECRET = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";

async function hmacHex(body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(SECRET), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (!SECRET) return new Response("payments not configured", { status: 503 });
  const body = await req.text();
  const given = req.headers.get("x-paystack-signature") ?? "";
  if (!safeEqual(await hmacHex(body), given)) return new Response("bad signature", { status: 401 });

  const event = JSON.parse(body);
  if (event.event !== "charge.success") return new Response("ignored");

  const reference: string = event.data?.reference ?? "";
  const check = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
    headers: { Authorization: `Bearer ${SECRET}` },
  }).then((r) => r.json());
  if (!check.status || check.data?.status !== "success" || check.data?.currency !== "NGN") {
    return new Response("not verified", { status: 400 });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.rpc("credit_purchase", { p_reference: reference, p_kobo: check.data.amount });
  if (error) {
    console.error("credit_purchase failed", error);
    return new Response("error", { status: 500 });       // Paystack will retry
  }
  return new Response("ok");
});
