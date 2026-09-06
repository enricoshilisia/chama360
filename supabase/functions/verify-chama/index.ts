// The target of the "Approve this chama" link in the notification email.
//
// It's a plain GET handler that returns a page, not a JSON API — the owner
// clicks the link in their mail client and lands here. The token is the
// entire credential, so it's long, single-use, and cleared on approval.
// On success the chairperson is emailed to say their chama is live.
//
// Deploy with JWT verification off, since a link clicked from an email
// carries no Supabase session:
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
  <div style="background:#fff;border-radius:20px;padding:40px;max-width:420px;text-align:center;
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

/** Tells the chairperson their chama is live. Best-effort: a mail failure
 *  must not make an approval that already happened look like it failed. */
async function notifyChairperson(
  toEmail: string,
  contactName: string,
  chamaName: string,
): Promise<boolean> {
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const mailFrom = Deno.env.get('MAIL_FROM') ?? 'Chama360 <onboarding@resend.dev>';
  if (!resendKey || !toEmail) return false;

  const safeName = escapeHtml(contactName || 'there');
  const safeChama = escapeHtml(chamaName);

  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:520px;margin:0 auto;padding:24px">
      <h2 style="margin:0 0 4px;color:#1a1a1a">${safeChama} is approved</h2>
      <p style="color:#555;font-size:15px;line-height:1.6;margin:16px 0">
        Hello ${safeName},
      </p>
      <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px">
        Your chama registration has been reviewed and approved. You can now sign in,
        add your members, and start recording contributions and loans.
      </p>
      <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 24px">
        Members without email addresses can be added by name, and you can give any of
        them a phone-number login when they're ready to use the app themselves.
      </p>
      <p style="color:#999;font-size:12px;margin:0">
        Chama360 — you're receiving this because you registered ${safeChama}.
      </p>
    </div>`;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: mailFrom,
        to: [toEmail],
        subject: `${chamaName} has been approved`,
        html,
      }),
    });
    if (!res.ok) console.error('Approval email rejected', await res.text());
    return res.ok;
  } catch (err) {
    console.error('Approval email failed to send', err);
    return false;
  }
}

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get('token');

  if (!token) {
    return page('Link incomplete', 'This verification link is missing its token.', false);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data, error } = await supabase.rpc('verify_chama_by_token', { p_token: token });

  if (error) {
    console.error('Verification failed', error.message);
    return page(
      'Link not valid',
      'This link has already been used, or it was never valid. Nothing has been changed.',
      false,
    );
  }

  const result = Array.isArray(data) ? data[0] : data;
  const chamaName = result?.chama_name ?? 'The chama';
  const contactEmail = result?.contact_email ?? '';
  const contactName = result?.contact_name ?? '';

  if (result?.already_verified) {
    return page('Already approved', `${escapeHtml(chamaName)} was approved earlier. Nothing to do.`, true);
  }

  const emailed = await notifyChairperson(contactEmail, contactName, chamaName);

  return page(
    'Chama approved',
    `${escapeHtml(chamaName)} is now active. ` +
      (emailed
        ? `${escapeHtml(contactEmail)} has been told it's live.`
        : 'Let the chairperson know they can start using it.'),
    true,
  );
});
