// Emails the platform owner when someone registers a new chama, with a
// one-click verification link. Until that link is clicked the chama can be
// looked at but not operated (see is_chama_active in 0005).
//
// Secrets required:
//   RESEND_API_KEY   from resend.com
//   OWNER_EMAIL      where approval requests go
//   MAIL_FROM        verified sender, e.g. "Chama360 <noreply@yourdomain>"
//                    (Resend's onboarding@resend.dev works for testing)
//
// Deploy: supabase functions deploy notify-chama-registration

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

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!
  ));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Not signed in' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const ownerEmail = Deno.env.get('OWNER_EMAIL');
  const mailFrom = Deno.env.get('MAIL_FROM') ?? 'Chama360 <onboarding@resend.dev>';

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: 'Not signed in' }, 401);

  let body: { chama_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (!body.chama_id) return json({ error: 'chama_id is required' }, 400);

  const admin = createClient(url, serviceKey);
  const { data: chama, error } = await admin
    .from('chamas')
    .select('id, name, description, contact_name, contact_phone, contact_email, created_by, status, verification_token, created_at')
    .eq('id', body.chama_id)
    .single();

  if (error || !chama) return json({ error: 'Chama not found' }, 404);

  // Only the person who registered it can trigger its notification, and
  // only while it's still pending — otherwise this is a way to spam the
  // owner's inbox with re-sends.
  if (chama.created_by !== user.id) return json({ error: 'Not your registration' }, 403);
  if (chama.status !== 'pending_verification') {
    return json({ error: 'This chama has already been reviewed' }, 409);
  }

  // No email configured yet: say so plainly rather than reporting success
  // for a mail nobody sent. The registration still stands and can be
  // approved straight from the database.
  if (!resendKey || !ownerEmail) {
    return json({
      sent: false,
      reason: 'Email is not configured (RESEND_API_KEY / OWNER_EMAIL missing)',
    });
  }

  const verifyUrl = `${url}/functions/v1/verify-chama?token=${chama.verification_token}`;
  const safe = {
    name: escapeHtml(chama.name ?? ''),
    description: escapeHtml(chama.description ?? '—'),
    contactName: escapeHtml(chama.contact_name ?? '—'),
    contactPhone: escapeHtml(chama.contact_phone ?? '—'),
    contactEmail: escapeHtml(chama.contact_email ?? '—'),
  };

  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:0 auto;padding:24px">
      <h2 style="margin:0 0 4px">New chama registration</h2>
      <p style="color:#666;margin:0 0 20px">Someone has registered a chama and is waiting on your approval.</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        <tr><td style="padding:8px 0;color:#666;width:130px">Chama</td><td style="padding:8px 0"><strong>${safe.name}</strong></td></tr>
        <tr><td style="padding:8px 0;color:#666">Description</td><td style="padding:8px 0">${safe.description}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Contact</td><td style="padding:8px 0">${safe.contactName}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Phone</td><td style="padding:8px 0">${safe.contactPhone}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Email</td><td style="padding:8px 0">${safe.contactEmail}</td></tr>
      </table>
      <p style="margin:28px 0">
        <a href="${verifyUrl}"
           style="background:#4E9950;color:#fff;padding:14px 24px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">
          Approve this chama
        </a>
      </p>
      <p style="color:#999;font-size:12px;margin:0">
        Until you approve it, this chama cannot add members or record any money.
        Ignore this email to leave it pending.
      </p>
    </div>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: mailFrom,
      to: [ownerEmail],
      subject: `Chama360 — approve "${chama.name}"`,
      html,
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    console.error('Resend rejected the message', detail);
    return json({ sent: false, reason: 'Email provider rejected the message' }, 502);
  }

  return json({ sent: true });
});
