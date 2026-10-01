// Starts a Paystack payment for a coin pack. WEB ONLY: inside the Android/iOS apps,
// Google Play and Apple require their own in-app purchase for digital coins.
// The price comes from the coin_packs table, never from the client.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (!Deno.env.get("PAYSTACK_SECRET_KEY")) {
    return Response.json({ error: "Coin purchases are not switched on yet." }, { status: 503, headers: cors });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return Response.json({ error: "Sign in first." }, { status: 401, headers: cors });
  if (!user.email) {
    return Response.json({ error: "Add an email address to your account to pay by card." }, { status: 400, headers: cors });
  }

  const { pack_id } = await req.json().catch(() => ({}));
  const reference = `na_${crypto.randomUUID().replace(/-/g, "")}`;
  const { data: pack, error } = await admin.rpc("create_purchase", {
    p_citizen: user.id, p_pack: String(pack_id ?? ""), p_reference: reference,
  });
  if (error) return Response.json({ error: error.message }, { status: 400, headers: cors });

  const res = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("PAYSTACK_SECRET_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: user.email,
      amount: pack.kobo,
      currency: "NGN",
      reference,
      callback_url: `${Deno.env.get("APP_ORIGIN")}/?paid=${reference}`,
      metadata: { citizen_id: user.id, pack_id: pack.id },
    }),
  });
  const body = await res.json();
  if (!body.status) return Response.json({ error: "Payment could not start. Try again." }, { status: 502, headers: cors });
  return Response.json({ authorization_url: body.data.authorization_url, reference }, { headers: cors });
});
