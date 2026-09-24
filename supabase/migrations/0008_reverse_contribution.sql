-- Reversing a contribution, rather than deleting it.
--
-- A chairperson who fishes the wrong amount or the wrong member into the
-- ledger needs a way out. Deleting the row is the wrong way out: the
-- member's running balance is maintained by an AFTER INSERT trigger, so a
-- delete would leave the balance permanently overstated, and the audit
-- trail would simply lose the entry — you could never tell a mistake that
-- was corrected from one that was covered up.
--
-- So we reverse instead. The original contribution stays, marked
-- 'reversed' with who did it, when and why; the member's balance is
-- reduced by exactly what it was increased by; and a matching negative
-- 'reversal' row is posted to the ledger. Two entries, one net effect of
-- zero — the double entry the chairperson asked for.
--
-- Everything that reports on money already filters on status = 'completed'
-- (see chama_totals() and ReportsRepository), so a reversed contribution
-- drops out of every total the moment it is reversed, with no further
-- changes needed.

-- ---------------------------------------------------------------- schema

alter table public.contributions
  drop constraint if exists contributions_status_check;

alter table public.contributions
  add constraint contributions_status_check
  check (status in ('pending', 'completed', 'failed', 'reversed'));

alter table public.contributions
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references public.profiles(id),
  add column if not exists reversal_reason text;

-- The ledger gains a type of its own for the counter-entry, so a reversal
-- is never mistaken for a withdrawal or a correction made by hand.
alter table public.transactions
  drop constraint if exists transactions_type_check;

alter table public.transactions
  add constraint transactions_type_check
  check (type in ('contribution', 'loan_disbursement', 'loan_repayment',
                  'penalty', 'withdrawal', 'reversal'));

-- ---------------------------------------------------------------- reverse

create or replace function public.reverse_contribution(
  p_contribution_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contribution public.contributions%rowtype;
  v_new_balance numeric(14,2);
  v_member_user uuid;
  v_chama_name text;
begin
  select * into v_contribution
  from public.contributions
  where id = p_contribution_id;

  if not found then
    raise exception 'That contribution no longer exists';
  end if;

  if not public.is_chama_admin(v_contribution.chama_id) then
    raise exception 'Only the chairperson or treasurer can reverse a contribution';
  end if;

  if v_contribution.status = 'reversed' then
    raise exception 'That contribution has already been reversed';
  end if;

  if v_contribution.status <> 'completed' then
    raise exception 'Only a completed contribution can be reversed';
  end if;

  -- Mandatory, for the same reason a loan rejection needs one: the member
  -- whose record just changed is owed an explanation.
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Give a reason for the reversal';
  end if;

  update public.contributions
     set status = 'reversed',
         reversed_at = now(),
         reversed_by = auth.uid(),
         reversal_reason = trim(p_reason)
   where id = p_contribution_id;

  update public.chama_members
     set balance = balance - v_contribution.amount
   where id = v_contribution.member_id
   returning balance, user_id into v_new_balance, v_member_user;

  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, balance_after)
  values
    (v_contribution.chama_id, v_contribution.member_id, 'reversal',
     -v_contribution.amount, v_contribution.id, v_new_balance);

  -- Tell the member, if they have a login of their own. A managed member
  -- has no account to notify; their chairperson is the one holding the
  -- record either way.
  if v_member_user is not null then
    select name into v_chama_name from public.chamas where id = v_contribution.chama_id;

    insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
    values (
      v_member_user,
      v_contribution.chama_id,
      'A contribution was reversed',
      'Your contribution of ' || to_char(v_contribution.amount, 'FM999,999,999.00') ||
      ' recorded on ' || to_char(v_contribution.contribution_date, 'DD Mon YYYY') ||
      ' in ' || coalesce(v_chama_name, 'your chama') ||
      ' has been reversed. Reason: ' || trim(p_reason),
      'contribution',
      v_contribution.id
    );
  end if;
end;
$$;

grant execute on function public.reverse_contribution(uuid, text) to authenticated;

-- ------------------------------------------------------- reading it back

-- The report needs the contribution's own id (to reverse it) and its
-- reversal state (to show it as struck through rather than pretend it
-- never happened). RLS on contributions is row-level and already correct
-- — this exists so the report can ask for reversed rows too, in one place,
-- with names resolved the same way chama_roster() resolves them.
create or replace function public.chama_contributions(p_chama_id uuid)
returns table (
  id uuid,
  member_id uuid,
  member_name text,
  amount numeric,
  contribution_date date,
  status text,
  notes text,
  reversal_reason text,
  reversed_at timestamptz
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

  select m.id into v_self
  from public.chama_members m
  where m.chama_id = p_chama_id and m.user_id = auth.uid();

  return query
  select
    c.id,
    c.member_id,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'Member'),
    c.amount,
    c.contribution_date,
    c.status,
    c.notes,
    c.reversal_reason,
    c.reversed_at
  from public.contributions c
  join public.chama_members m on m.id = c.member_id
  left join public.profiles p on p.id = m.user_id
  where c.chama_id = p_chama_id
    and c.status in ('completed', 'reversed')
    -- Same rule as the RLS policy this replaces: admins see the chama,
    -- everyone else sees only themselves.
    and (v_is_admin or c.member_id = v_self)
  order by c.contribution_date desc, c.created_at desc;
end;
$$;

grant execute on function public.chama_contributions(uuid) to authenticated;
