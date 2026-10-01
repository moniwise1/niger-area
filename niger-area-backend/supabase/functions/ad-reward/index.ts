// Google AdMob server-side verification (SSV) callback.
// AdMob calls this URL after a player finishes a rewarded ad. We only credit coins when
// Google's ECDSA signature checks out, so a player can't fake "I watched an ad" from the client.
// Set the ad's SSV user id to the player's Supabase user id in the app:
//   ServerSideVerificationOptions.Builder().setUserId(session.user.id)
import { createClient } from "jsr:@supabase/supabase-js@2";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
let keyCache: { at: number; keys: Map<string, CryptoKey> } | null = null;

async function verifierKeys(): Promise<Map<string, CryptoKey>> {
  if (keyCache && Date.now() - keyCache.at < 6 * 3600_000) return keyCache.keys;
  const res = await fetch(KEYS_URL);
  const body: { keys: { keyId: number; base64: string }[] } = await res.json();
  const keys = new Map<string, CryptoKey>();
  for (const k of body.keys) {
    const der = Uint8Array.from(atob(k.base64), (c) => c.charCodeAt(0));
    keys.set(String(k.keyId), await crypto.subtle.importKey(
      "spki", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]));
  }
  keyCache = { at: Date.now(), keys };
  return keys;
}

function b64urlToBytes(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

// AdMob signs with DER-encoded ECDSA; WebCrypto wants raw r||s (64 bytes).
function derToRaw(der: Uint8Array): Uint8Array {
  let i = 2;                                   // skip SEQUENCE tag + length
  if (der[1] & 0x80) i += der[1] & 0x7f;
  const read = () => {
    i++;                                       // INTEGER tag
    const len = der[i++];
    let v = der.slice(i, i + len);
    i += len;
    while (v.length > 32 && v[0] === 0) v = v.slice(1);
    const out = new Uint8Array(32);
    out.set(v, 32 - v.length);
    return out;
  };
  const raw = new Uint8Array(64);
  raw.set(read(), 0);
  raw.set(read(), 32);
  return raw;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const raw = url.search.slice(1);
  const sigAt = raw.indexOf("&signature=");
  if (sigAt < 0) return new Response("missing signature", { status: 400 });

  const message = new TextEncoder().encode(raw.slice(0, sigAt));
  const params = url.searchParams;
  const signature = params.get("signature") ?? "";
  const keyId = params.get("key_id") ?? "";
  const userId = params.get("user_id") ?? "";
  const txn = params.get("transaction_id") ?? "";

  const key = (await verifierKeys()).get(keyId);
  if (!key) return new Response("unknown key", { status: 400 });
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, key, derToRaw(b64urlToBytes(signature)), message);
  if (!valid) return new Response("bad signature", { status: 403 });
  if (!/^[0-9a-f-]{36}$/.test(userId) || !txn) return new Response("bad params", { status: 400 });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.rpc("credit_ad_reward", { p_citizen: userId, p_txn: txn });
  if (error) {
    console.error("credit_ad_reward failed", error);
    return new Response("error", { status: 500 });
  }
  // 200 even when the daily cap is hit, so AdMob doesn't retry.
  return new Response("ok");
});
