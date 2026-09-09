// Resets an existing member's password to a fresh temporary one.
//
// Same shape as create-member-login, and for the same reason: changing
// someone else's password needs the service-role key, which must never
// ship inside the Flutter app. The caller's own JWT is checked first, so
// only a chairperson/treasurer of that specific chama can do it.
//
// The new password comes back exactly once and is never stored in readable
// form. The member is forced to replace it on their next sign-in, which
// also means a chairperson can't quietly keep using a member's account:
// the moment the member logs in, the temporary password stops working.
//
// Deploy: supabase functions deploy reset-member-password

import { createClient } from 'jsr:@supabase/supabase-js@2';

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

/**
 * Readable but not guessable — avoids the character pairs people misread
 * when a password is relayed over WhatsApp or read aloud (0/O, 1/l/I).
 * Kept identical to create-member-login so members see a familiar shape.
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

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: 'Not signed in' }, 401);

  let body: { chama_id?: string; member_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }

  const { chama_id, member_id } = body;
  if (!chama_id || !member_id) {
    return json({ error: 'chama_id and member_id are required' }, 400);
  }

  // Asked as the caller, so passing someone else's chama_id proves nothing.
  const { data: isAdmin, error: adminError } = await caller.rpc('is_chama_admin', {
    p_chama_id: chama_id,
  });
  if (adminError) return json({ error: adminError.message }, 400);
  if (!isAdmin) {
    return json({ error: 'Only the chairperson or treasurer can do this' }, 403);
  }

  const admin = createClient(url, serviceKey);

  const { data: member, error: memberError } = await admin
    .from('chama_members')
    .select('id, chama_id, user_id, full_name, phone, role')
    .eq('id', member_id)
    .single();

  if (memberError || !member) return json({ error: 'Member not found' }, 404);
  if (member.chama_id !== chama_id) {
    return json({ error: 'That member belongs to a different chama' }, 403);
  }
  if (!member.user_id) {
    return json({ error: 'This member does not have a login yet' }, 409);
  }

  // Refuse to reset a chairperson's own password through this route. An
  // admin resetting a peer admin — or themselves — would be a way to take
  // over an account rather than help someone locked out; that belongs in
  // the normal password-reset-by-email flow.
  if (member.user_id === user.id) {
    return json({ error: 'Use "Forgot password" to change your own password' }, 400);
  }
  if (member.role === 'chairperson') {
    return json({ error: 'A chairperson\'s password cannot be reset from here' }, 403);
  }

  const tempPassword = generateTempPassword();

  // Preserve whatever metadata the account already carries, then force a
  // change on next sign-in. Overwriting user_metadata wholesale here would
  // wipe their name and phone.
  const { data: existing } = await admin.auth.admin.getUserById(member.user_id);

  const { error: updateError } = await admin.auth.admin.updateUserById(member.user_id, {
    password: tempPassword,
    user_metadata: {
      ...(existing?.user?.user_metadata ?? {}),
      must_change_password: true,
    },
  });

  if (updateError) return json({ error: updateError.message }, 400);

  return json({
    member_name: member.full_name ?? 'Member',
    phone: member.phone ?? '',
    temporary_password: tempPassword,
    message: 'Share this with the member. They must change it when they next sign in.',
  });
});
