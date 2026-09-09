/** Proposals carry bigints (wei, nonce). JSON.stringify throws on those, so render them as strings. */
export function json(data: unknown, status = 200): Response {
  const body = JSON.stringify(data, (_k, v) => (typeof v === "bigint" ? v.toString() : v));
  return new Response(body, { status, headers: { "content-type": "application/json" } });
}

export function fail(message: string, status = 400): Response {
  return json({ error: message }, status);
}
