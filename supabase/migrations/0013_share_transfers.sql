-- Moving one member's shares to another.
--
-- A member leaves and sells their stake to someone still in; a parent
-- passes theirs to a child; two people settle something between them
-- inside the chama. The pot does not change — the chama holds exactly
-- what it held before — only who owns what does. So this never touches
-- the contributions table: what somebody paid in, and when, is a
-- historical fact and must not be rewritten by a later transfer.
--
-- What moves is the balance. What is recorded is everything: who moved
-- it, out of whose name, into whose, how much, why, and when. Both
-- members are told, by name, where it went or where it came from.

create table if not exists public.share_transfers (
  id uuid primary key default gen_random_uuid(),
  chama_id uuid not null references public.chamas(id) on delete cascade,
  from_member_id uuid not null references public.chama_members(id) on delete restrict,
  to_member_id uuid not null references public.chama_members(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  reason text not null,
  -- Who performed it. Not nullable: a transfer with no author is not an
  -- audit record, it is a rumour.
  transferred_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint share_transfers_distinct_members check (from_member_id <> to_member_id)
);

create index if not exists idx_share_transfers_chama
  on public.share_transfers (chama_id, created_at desc);
create index if not exists idx_share_transfers_from on public.share_transfers (from_member_id);
create index if not exists idx_share_transfers_to on public.share_transfers (to_member_id);

alter table public.share_transfers enable row level security;

-- Admins see every transfer in their chama. Everyone else sees only the
-- ones they were part of — which they must, because it changed what they
-- hold.
drop policy if exists share_transfers_select on public.share_transfers;
create policy share_transfers_select on public.share_transfers
  for select using (
    public.is_chama_admin(chama_id)
    or from_member_id in (
      select cm.id from public.chama_members cm
      where cm.chama_id = share_transfers.chama_id and cm.user_id = auth.uid()
    )
    or to_member_id in (
      select cm.id from public.chama_members cm
      where cm.chama_id = share_transfers.chama_id and cm.user_id = auth.uid()
    )
  );

-- No insert, update or delete policy at all. The only way a row gets in
-- here is transfer_shares(), which moves the balances in the same
-- transaction; a hand-written row would be an audit entry for something
-- that never happened.

-- The ledger needs somewhere to put the two halves.
alter table public.transactions
  drop constraint if exists transactions_type_check;

alter table public.transactions
  add constraint transactions_type_check
  check (type in ('contribution', 'loan_disbursement', 'loan_repayment',
                  'penalty', 'withdrawal', 'reversal',
                  'share_transfer_in', 'share_transfer_out'));

-- ------------------------------------------------------------- the move

create or replace function public.transfer_shares(
  p_chama_id uuid,
  p_from_member_id uuid,
  p_to_member_id uuid,
  p_amount numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from public.chama_members%rowtype;
  v_to public.chama_members%rowtype;
  v_from_name text;
  v_to_name text;
  v_from_balance numeric(14,2);
  v_to_balance numeric(14,2);
  v_transfer_id uuid;
  v_chama_name text;
  v_amount numeric(14,2);
begin
  if not public.is_chama_admin(p_chama_id) then
    raise exception 'Only the chairperson or treasurer can transfer shares';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is not active';
  end if;

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount <= 0 then
    raise exception 'Enter an amount to transfer';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Give a reason for the transfer';
  end if;

  if p_from_member_id = p_to_member_id then
    raise exception 'Pick two different members';
  end if;

  -- Lock both rows, lowest id first, so two transfers running at once
  -- cannot deadlock against each other or read a balance that is about
  -- to change underneath them.
  if p_from_member_id < p_to_member_id then
    select * into v_from from public.chama_members where id = p_from_member_id for update;
    select * into v_to   from public.chama_members where id = p_to_member_id   for update;
  else
    select * into v_to   from public.chama_members where id = p_to_member_id   for update;
    select * into v_from from public.chama_members where id = p_from_member_id for update;
  end if;

  if v_from.id is null or v_from.chama_id <> p_chama_id or v_from.status <> 'active' then
    raise exception 'The member transferring is not active in this chama';
  end if;
  if v_to.id is null or v_to.chama_id <> p_chama_id or v_to.status <> 'active' then
    raise exception 'The member receiving is not active in this chama';
  end if;

  -- Nobody can give away more than they hold. Without this a transfer
  -- would quietly invent shares and the chama's books would stop adding
  -- up against what its members actually paid in.
  if v_from.balance < v_amount then
    raise exception 'That is more than % holds (%)',
      coalesce(nullif(trim(v_from.full_name), ''), 'that member'),
      to_char(v_from.balance, 'FM999,999,990.00');
  end if;

  select coalesce(nullif(trim(p.full_name), ''), v_from.full_name, 'A member')
    into v_from_name
  from public.chama_members m left join public.profiles p on p.id = m.user_id
  where m.id = v_from.id;

  select coalesce(nullif(trim(p.full_name), ''), v_to.full_name, 'A member')
    into v_to_name
  from public.chama_members m left join public.profiles p on p.id = m.user_id
  where m.id = v_to.id;

  select name into v_chama_name from public.chamas where id = p_chama_id;

  update public.chama_members set balance = balance - v_amount
   where id = v_from.id returning balance into v_from_balance;

  update public.chama_members set balance = balance + v_amount
   where id = v_to.id returning balance into v_to_balance;

  insert into public.share_transfers
    (chama_id, from_member_id, to_member_id, amount, reason, transferred_by)
  values
    (p_chama_id, v_from.id, v_to.id, v_amount, trim(p_reason), auth.uid())
  returning id into v_transfer_id;

  -- Both halves on the ledger, each naming the other side, so neither
  -- member's history shows money appearing or vanishing unexplained.
  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at, note)
  values
    (p_chama_id, v_from.id, 'share_transfer_out', -v_amount, v_transfer_id,
     v_from_balance, now(), 'To ' || v_to_name || ' - ' || trim(p_reason)),
    (p_chama_id, v_to.id, 'share_transfer_in', v_amount, v_transfer_id,
     v_to_balance, now(), 'From ' || v_from_name || ' - ' || trim(p_reason));

  -- Tell whichever of them has an account. A member the chairperson
  -- manages has nobody to notify; the record stands either way.
  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select v_from.user_id, p_chama_id, 'Shares transferred out',
         to_char(v_amount, 'FM999,999,990.00') || ' of your shares in ' ||
         coalesce(v_chama_name, 'the chama') || ' were transferred to ' || v_to_name ||
         '. Reason: ' || trim(p_reason) ||
         '. You now hold ' || to_char(v_from_balance, 'FM999,999,990.00') || '.',
         'member', v_from.id
  where v_from.user_id is not null;

  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select v_to.user_id, p_chama_id, 'Shares transferred to you',
         'You received ' || to_char(v_amount, 'FM999,999,990.00') || ' in shares from ' ||
         v_from_name || ' in ' || coalesce(v_chama_name, 'the chama') ||
         '. Reason: ' || trim(p_reason) ||
         '. You now hold ' || to_char(v_to_balance, 'FM999,999,990.00') || '.',
         'member', v_to.id
  where v_to.user_id is not null;

  return v_transfer_id;
end;
$$;

grant execute on function public.transfer_shares(uuid, uuid, uuid, numeric, text) to authenticated;

-- ------------------------------------------------------------ the audit

-- Who moved what, between whom, and why — with names resolved and the
-- same own-or-admin rule the table enforces, so a member can see the
-- transfers that changed what they hold and nothing else.
create or replace function public.chama_share_transfers(p_chama_id uuid)
returns table (
  id uuid,
  amount numeric,
  reason text,
  created_at timestamptz,
  from_member_id uuid,
  from_name text,
  to_member_id uuid,
  to_name text,
  performed_by_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_self uuid;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_admin(p_chama_id);
  select m.id into v_self from public.chama_members m
   where m.chama_id = p_chama_id and m.user_id = auth.uid();

  return query
  select
    t.id,
    t.amount,
    t.reason,
    t.created_at,
    t.from_member_id,
    coalesce(nullif(trim(pf.full_name), ''), mf.full_name, 'A member'),
    t.to_member_id,
    coalesce(nullif(trim(pt.full_name), ''), mt.full_name, 'A member'),
    coalesce(nullif(trim(pb.full_name), ''), pb.email, 'An administrator')
  from public.share_transfers t
  join public.chama_members mf on mf.id = t.from_member_id
  join public.chama_members mt on mt.id = t.to_member_id
  left join public.profiles pf on pf.id = mf.user_id
  left join public.profiles pt on pt.id = mt.user_id
  left join public.profiles pb on pb.id = t.transferred_by
  where t.chama_id = p_chama_id
    and (v_is_admin or t.from_member_id = v_self or t.to_member_id = v_self)
  order by t.created_at desc;
end;
$$;

grant execute on function public.chama_share_transfers(uuid) to authenticated;
