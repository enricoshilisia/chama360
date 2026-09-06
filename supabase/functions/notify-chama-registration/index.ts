// Emails the platform owner when a chama registration is submitted, with a
// one-click approval link.
//
// Called by someone with no account — that's the whole design: nobody gets
// an account until the owner approves. So this function can't authenticate
// its caller. Instead it takes only a registration id, looks the row up
// itself, and mails a fixed address (OWNER_EMAIL). Nothing a caller sends
// can redirect the mail or reveal anything: the response says only whether
// a message went out.
//
// Deploy without JWT verification, since the applicant has no session:
//   supabase functions deploy notify-chama-registration --no-verify-jwt

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

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const ownerEmail = Deno.env.get('OWNER_EMAIL');
  const mailFrom = Deno.env.get('MAIL_FROM') ?? 'Chama360 <onboarding@resend.dev>';

  let body: { registration_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
  if (!body.registration_id) return json({ error: 'registration_id is required' }, 400);

  const admin = createClient(url, serviceKey);
  const { data: reg, error } = await admin
    .from('chama_registrations')
    .select('id, chama_name, description, contact_name, contact_phone, contact_email, status, verification_token')
    .eq('id', body.registration_id)
    .single();

  // Deliberately vague: a caller guessing ids learns nothing about which
  // ones exist.
  if (error || !reg) return json({ sent: false }, 200);
  if (reg.status !== 'pending') return json({ sent: false }, 200);

  if (!resendKey || !ownerEmail) {
    console.error('Email not configured — RESEND_API_KEY or OWNER_EMAIL missing');
    return json({ sent: false, reason: 'email_not_configured' });
  }

  const approveUrl = `${url}/functions/v1/verify-chama?token=${reg.verification_token}`;
  const safe = {
    name: escapeHtml(reg.chama_name ?? ''),
    description: escapeHtml(reg.description ?? '—'),
    contactName: escapeHtml(reg.contact_name ?? '—'),
    contactPhone: escapeHtml(reg.contact_phone ?? '—'),
    contactEmail: escapeHtml(reg.contact_email ?? '—'),
  };

  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:0 auto;padding:24px">
      <h2 style="margin:0 0 4px">New chama registration</h2>
      <p style="color:#666;margin:0 0 20px">
        Someone has applied to run a chama. No account has been created yet —
        approving this creates it and invites them in.
      </p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        <tr><td style="padding:8px 0;color:#666;width:130px">Chama</td><td style="padding:8px 0"><strong>${safe.name}</strong></td></tr>
        <tr><td style="padding:8px 0;color:#666">Description</td><td style="padding:8px 0">${safe.description}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Chairperson</td><td style="padding:8px 0">${safe.contactName}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Phone</td><td style="padding:8px 0">${safe.contactPhone}</td></tr>
        <tr><td style="padding:8px 0;color:#666">Email</td><td style="padding:8px 0">${safe.contactEmail}</td></tr>
      </table>
      <p style="margin:28px 0">
        <a href="${approveUrl}"
           style="background:#4E9950;color:#fff;padding:14px 24px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">
          Approve this registration
        </a>
      </p>
      <p style="color:#999;font-size:12px;margin:0">
        Ignore this email to leave the application pending. Nothing exists on the
        platform until you approve it.
      </p>
    </div>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: mailFrom,
      to: [ownerEmail],
      subject: `Chama360 — approve "${reg.chama_name}"`,
      html,
    }),
  });

  if (!res.ok) {
    console.error('Resend rejected the message', await res.text());
    return json({ sent: false, reason: 'provider_rejected' }, 502);
  }

  return json({ sent: true });
});
