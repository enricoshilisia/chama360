// The target of the "Approve this registration" link in the owner's email.
//
// This is where a chama actually comes into existence. Before this click
// there is no chama, no account, nothing but an application row — which is
// the point: nobody gets a foothold on the platform until the owner says
// so.
//
// On approval, in order:
//   1. approve_chama_registration()  provisions the chama (SQL)
//   2. inviteUserByEmail()           creates the chairperson's account and
//                                    makes Supabase send them the invite —
//                                    this is the "confirmation" email, and
//                                    it can only happen after approval
//   3. attach_chairperson()          links that account to the chama
//
// Resend is not involved here. It only ever tells the owner a registration
// arrived; everything facing the chairperson is Supabase's own auth mail.
//
// Deploy with JWT verification off — a link clicked from an email carries
// no session:
//   supabase functions deploy verify-chama --no-verify-jwt

import { createClient } from 'jsr:@supabase/supabase-js@2';

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!
  ));
}

function page(title: string, message: string, ok: boolean): Response {
  const accent = ok ? '#4E9950' : '#C0392B';
  return new Response(
    `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
</head>
<body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F3F8F3;margin:0;
             min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px">
  <div style="background:#fff;border-radius:20px;padding:40px;max-width:440px;text-align:center;
              box-shadow:0 10px 40px rgba(0,0,0,.08)">
    <div style="width:56px;height:56px;border-radius:50%;background:${accent}1A;color:${accent};
                font-size:28px;line-height:56px;margin:0 auto 20px">${ok ? '&#10003;' : '!'}</div>
    <h1 style="font-size:20px;margin:0 0 8px;color:#1a1a1a">${escapeHtml(title)}</h1>
    <p style="color:#666;font-size:14px;line-height:1.5;margin:0">${message}</p>
  </div>
</body>
</html>`,
    { status: ok ? 200 : 400, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
  );
}

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get('token');

  if (!token) {
    return page('Link incomplete', 'This approval link is missing its token.', false);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  // 1. Provision the chama.
  const { data, error } = await admin.rpc('approve_chama_registration', { p_token: token });

  if (error) {
    console.error('Approval failed', error.message);
    return page(
      'Link not valid',
      'This link has already been used, or it was never valid. Nothing has been changed.',
      false,
    );
  }

  const result = Array.isArray(data) ? data[0] : data;
  const chamaName = result?.chama_name ?? 'The chama';
  const chamaId = result?.chama_id as string | undefined;
  const contactEmail = (result?.contact_email ?? '') as string;
  const contactName = (result?.contact_name ?? '') as string;

  if (result?.already_approved) {
    return page(
      'Already approved',
      `${escapeHtml(chamaName)} was approved earlier. Nothing to do.`,
      true,
    );
  }

  // 2. Create the chairperson's account. Supabase sends the invite email as
  //    part of this call — the chairperson's first contact from us, and
  //    only now that approval has happened.
  let invitedUserId: string | null = null;
  let inviteFailure: string | null = null;

  // redirectTo is a custom scheme, so tapping the invite reopens the app
  // rather than a web page — supabase_flutter reads the tokens off the
  // link and signs them in. must_change_password sends them straight to
  // the set-a-password screen, since an invited account has none yet.
  const redirectTo = Deno.env.get('AUTH_REDIRECT_URL') ?? 'com.enrico.chama360://auth/callback';

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(
    contactEmail,
    {
      redirectTo,
      data: {
        full_name: contactName,
        role: 'chairperson',
        must_change_password: true,
      },
    },
  );

  if (inviteError) {
    // Most likely: this email already has an account from an earlier life.
    // Fall back to linking the existing account rather than stranding the
    // chama with no owner.
    console.error('Invite failed', inviteError.message);
    const { data: existing } = await admin.auth.admin.listUsers();
    const match = existing?.users?.find(
      (u) => (u.email ?? '').toLowerCase() === contactEmail.toLowerCase(),
    );
    if (match) {
      invitedUserId = match.id;
    } else {
      inviteFailure = inviteError.message;
    }
  } else {
    invitedUserId = invited?.user?.id ?? null;
  }

  // 3. Attach whoever we ended up with to the chama.
  if (chamaId && invitedUserId) {
    const { error: attachError } = await admin.rpc('attach_chairperson', {
      p_chama_id: chamaId,
      p_user_id: invitedUserId,
    });
    if (attachError) console.error('Could not attach chairperson', attachError.message);
  }

  if (inviteFailure) {
    return page(
      'Approved, but the invite did not send',
      `${escapeHtml(chamaName)} is active, but we could not email ` +
        `${escapeHtml(contactEmail)} (${escapeHtml(inviteFailure)}). ` +
        'They will need to be invited manually.',
      false,
    );
  }

  return page(
    'Chama approved',
    `${escapeHtml(chamaName)} is now active, and ${escapeHtml(contactEmail)} has been ` +
      'emailed an invitation to set their password and sign in.',
    true,
  );
});
