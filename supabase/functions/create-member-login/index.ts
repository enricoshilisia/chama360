// Creates a phone-based login for an existing chama member.
//
// This has to be server-side: creating an account *for someone else* needs
// the service-role key, which must never ship inside the Flutter app. The
// caller's own JWT is checked first so only a chairperson/treasurer of that
// specific chama can do it.
//
// Returns the temporary password exactly once. It is never stored anywhere
// in readable form — the chairperson relays it to the member and the member
// is forced to replace it on first login.
//
// Deploy: supabase functions deploy create-member-login

import { createClient } from 'jsr:@supabase/supabase-js@2';

const MEMBER_EMAIL_DOMAIN = 'members.chama360.app';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/** Same normalisation as lib/core/utils/phone_identity.dart — keep in step. */
function normalizePhone(raw: string): string {
  let digits = (raw ?? '').replace(/\D/g, '');
  if (digits.startsWith('254')) {
    // already country-coded
  } else if (digits.startsWith('0')) {
    digits = '254' + digits.slice(1);
  } else if (digits.length === 9) {
    digits = '254' + digits;
  }
  return digits;
}

/**
 * Readable but not guessable — avoids the character pairs people misread
 * when a password is relayed over WhatsApp or read aloud (0/O, 1/l/I).
 */
function generateTempPassword(): string {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnpqrstuvwxyz';
  const digits = '23456789';
  const pick = (set: string, n: number) =>
    Array.from(
      crypto.getRandomValues(new Uint32Array(n)),
      (v) => set[v % set.length],
    ).join('');
  return `${pick(upper, 2)}${pick(lower, 3)}${pick(digits, 3)}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Not signed in' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Acts as the caller — RLS and the is_chama_admin check apply to them,
  // not to us.
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: 'Not signed in' }, 401);

  let body: { chama_id?: string; member_id?: string; phone?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }

  const { chama_id, member_id, phone } = body;
  if (!chama_id || !member_id || !phone) {
    return json({ error: 'chama_id, member_id and phone are all required' }, 400);
  }

  const normalized = normalizePhone(phone);
  if (normalized.length !== 12 || !normalized.startsWith('254')) {
    return json({ error: 'Enter a valid Kenyan phone number' }, 400);
  }

  // Is the caller actually an admin of this chama? Asked as the caller, so
  // it can't be spoofed by passing someone else's chama_id.
  const { data: isAdmin, error: adminError } = await caller.rpc('is_chama_admin', {
    p_chama_id: chama_id,
  });
  if (adminError) return json({ error: adminError.message }, 400);
  if (!isAdmin) {
    return json({ error: 'Only the chairperson or treasurer can do this' }, 403);
  }

  const admin = createClient(url, serviceKey);

  // The chama has to be verified before it can onboard anyone.
  const { data: chama } = await admin
    .from('chamas')
    .select('status')
    .eq('id', chama_id)
    .single();
  if (!chama || chama.status !== 'active') {
    return json({ error: 'This chama is still awaiting verification' }, 400);
  }

  // The member must belong to this chama and not already have a login.
  const { data: member, error: memberError } = await admin
    .from('chama_members')
    .select('id, chama_id, user_id, full_name')
    .eq('id', member_id)
    .single();

  if (memberError || !member) return json({ error: 'Member not found' }, 404);
  if (member.chama_id !== chama_id) {
    return json({ error: 'That member belongs to a different chama' }, 403);
  }
  if (member.user_id) {
    return json({ error: 'This member already has a login' }, 409);
  }

  const email = `${normalized}@${MEMBER_EMAIL_DOMAIN}`;
  const tempPassword = generateTempPassword();

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password: tempPassword,
    email_confirm: true, // synthetic address; nothing to confirm
    user_metadata: {
      full_name: member.full_name ?? 'Member',
      phone: normalized,
      must_change_password: true,
    },
  });

  if (createError) {
    const already = createError.message?.toLowerCase().includes('already');
    return json(
      { error: already ? 'That phone number already has a login' : createError.message },
      already ? 409 : 400,
    );
  }

  // Attach the new account to the member row. If this fails the account
  // would be orphaned — delete it rather than leave a login nobody owns.
  const { error: linkError } = await admin
    .from('chama_members')
    .update({ user_id: created.user.id, phone: normalized })
    .eq('id', member_id);

  if (linkError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: 'Could not link the login to this member' }, 500);
  }

  return json({
    phone: normalized,
    temporary_password: tempPassword,
    message: 'Share this with the member. They must change it when they first sign in.',
  });
});
