import { z } from "zod";
import { addressSchema } from "@tappy/protocol";
import { listContacts, setContacts } from "~/server/tappy/store";
import { fail, json } from "~/server/tappy/json";

export const dynamic = "force-dynamic";

const contactSchema = z.object({
  id: z.string(),
  name: z.string().min(1),
  handle: z.string(),
  address: addressSchema,
});

export async function GET() {
  return json({ contacts: listContacts() });
}

/** The phone owns the list; the hub mirrors it so the agent can resolve a name to an address. */
export async function POST(req: Request) {
  const parsed = z
    .object({ contacts: z.array(contactSchema) })
    .safeParse(await req.json().catch(() => null));
  if (!parsed.success) return fail("expected { contacts: [{ id, name, handle, address }] }");

  setContacts(parsed.data.contacts);
  return json({ count: parsed.data.contacts.length });
}
