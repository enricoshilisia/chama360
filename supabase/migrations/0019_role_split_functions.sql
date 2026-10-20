-- Point each function at the right question.
--
-- Generated from the live definitions rather than retyped, so nothing
-- drifts from what was actually running. Money moves to the treasurer,
-- full visibility opens to any officer, and the roster functions keep
-- is_chama_admin so the chama can always appoint a new treasurer.

CREATE OR REPLACE FUNCTION public.approve_loan(p_loan_id uuid, p_interest_rate numeric DEFAULT 0, p_due_date date DEFAULT NULL::date, p_interest_period text DEFAULT 'one_off'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_loan public.loans%rowtype;
begin
  select * into v_loan from public.loans where id = p_loan_id;

  if not found then
    raise exception 'That loan request no longer exists';
  end if;

  if not public.is_chama_treasurer(v_loan.chama_id) then
    raise exception 'Only the treasurer can approve a loan';
  end if;

  if v_loan.status not in ('pending', 'rejected') then
    raise exception 'That loan has already been decided';
  end if;

  if coalesce(p_interest_period, 'one_off') <> 'one_off'
     and coalesce(p_interest_rate, 0) > 0
     and p_due_date is null then
    raise exception 'A loan charged per month or per year needs a due date';
  end if;

  update public.loans
     set status = 'active',
         interest_rate = coalesce(p_interest_rate, 0),
         interest_period = coalesce(p_interest_period, 'one_off'),
         due_date = p_due_date,
         approved_by = auth.uid(),
         decided_by = auth.uid(),
         decided_at = now(),
         rejection_reason = null
   where id = p_loan_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reject_loan(p_loan_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_loan record;
begin
  select * into v_loan from public.loans where id = p_loan_id;
  if v_loan is null then
    raise exception 'Loan not found';
  end if;
  if not public.is_chama_treasurer(v_loan.chama_id) then
    raise exception 'Only the treasurer can decide on a loan';
  end if;
  if length(coalesce(trim(p_reason), '')) < 3 then
    raise exception 'Give a reason for the rejection';
  end if;
  if v_loan.status = 'active' or v_loan.status = 'repaid' then
    raise exception 'This loan has already been disbursed';
  end if;

  update public.loans
    set status = 'rejected',
        rejection_reason = trim(p_reason),
        decided_at = now(),
        decided_by = auth.uid()
    where id = p_loan_id;

  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select m.user_id, v_loan.chama_id, 'Loan not approved',
         'Your request was not approved: ' || trim(p_reason),
         'loan', p_loan_id
  from public.chama_members m
  where m.id = v_loan.member_id and m.user_id is not null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_loan_for_member(p_chama_id uuid, p_member_id uuid, p_principal numeric, p_interest_rate numeric DEFAULT 0, p_purpose text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_interest_period text DEFAULT 'one_off'::text, p_issued_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_loan_id uuid;
  v_issued timestamptz;
begin
  if not public.is_chama_treasurer(p_chama_id) then
    raise exception 'Only the treasurer can record a loan';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is still awaiting verification';
  end if;

  if not exists (
    select 1 from public.chama_members m
    where m.id = p_member_id and m.chama_id = p_chama_id and m.status = 'active'
  ) then
    raise exception 'That member is not in this chama';
  end if;

  v_issued := coalesce(p_issued_at, now());

  -- Money cannot have been lent in a future the chama has not reached.
  if v_issued > now() then
    raise exception 'A loan cannot be dated in the future';
  end if;

  -- A rate charged per month or per year is meaningless without knowing
  -- how long the loan runs.
  if coalesce(p_interest_period, 'one_off') <> 'one_off'
     and coalesce(p_interest_rate, 0) > 0
     and p_due_date is null then
    raise exception 'A loan charged per month or per year needs a due date';
  end if;

  if p_due_date is not null and p_due_date < v_issued::date then
    raise exception 'The due date is before the loan was taken out';
  end if;

  insert into public.loans
    (chama_id, member_id, principal, interest_rate, interest_period,
     purpose, due_date, status, approved_by, issued_at)
  values
    (p_chama_id, p_member_id, p_principal, coalesce(p_interest_rate, 0),
     coalesce(p_interest_period, 'one_off'),
     p_purpose, p_due_date, 'pending', auth.uid(), v_issued)
  returning id into v_loan_id;

  -- Activating is what computes total_due and writes the ledger entry,
  -- both of which read issued_at â€” so it has to be set before this.
  update public.loans set status = 'active' where id = v_loan_id;

  return v_loan_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_contribution(p_contribution_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  if not public.is_chama_treasurer(v_contribution.chama_id) then
    raise exception 'Only the treasurer can reverse a contribution';
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

  -- A reversal is dated when it happens, not when the contribution it
  -- cancels was made: it is its own entry in the ledger, not an edit.
  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at, note)
  values
    (v_contribution.chama_id, v_contribution.member_id, 'reversal',
     -v_contribution.amount, v_contribution.id, v_new_balance, now(), trim(p_reason));

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
$function$;

CREATE OR REPLACE FUNCTION public.import_contributions(p_chama_id uuid, p_rows jsonb)
 RETURNS TABLE(inserted integer, duplicates integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row jsonb;
  v_index integer := 0;
  v_member uuid;
  v_amount numeric;
  v_date date;
  v_notes text;
  v_inserted integer := 0;
  v_duplicates integer := 0;
begin
  if not public.is_chama_treasurer(p_chama_id) then
    raise exception 'Only the treasurer can import contributions';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is not active';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Nothing to import';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return query select 0, 0;
    return;
  end if;

  if jsonb_array_length(p_rows) > 5000 then
    raise exception 'That file has more than 5000 contributions â€” split it and import in parts';
  end if;

  perform set_config('app.bulk_import', 'on', true);

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    v_member := nullif(v_row->>'member_id', '')::uuid;
    v_amount := nullif(v_row->>'amount', '')::numeric;
    v_date := nullif(v_row->>'date', '')::date;
    v_notes := nullif(trim(coalesce(v_row->>'notes', '')), '');

    -- The client checks all of this too, and says which sheet and row is
    -- at fault. These are the backstop: a bad row aborts the whole
    -- import rather than landing half a file.
    if v_member is null then
      raise exception 'Row % does not say who it belongs to', v_index;
    end if;

    if not exists (
      select 1 from public.chama_members m
      where m.id = v_member and m.chama_id = p_chama_id and m.status = 'active'
    ) then
      raise exception 'Row % refers to someone who is not an active member of this chama', v_index;
    end if;

    if v_amount is null or v_amount <= 0 then
      raise exception 'Row % has no usable amount', v_index;
    end if;

    if v_date is null then
      raise exception 'Row % has no usable date', v_index;
    end if;

    if v_date > current_date then
      raise exception 'Row % is dated in the future', v_index;
    end if;

    -- Re-uploading a sheet after adding a few more lines is how people
    -- actually work, so an identical row is skipped instead of doubling
    -- someone's total. Reported back, so nothing goes missing silently.
    if exists (
      select 1 from public.contributions c
      where c.chama_id = p_chama_id
        and c.member_id = v_member
        and c.contribution_date = v_date
        and c.amount = v_amount
        and c.status = 'completed'
    ) then
      v_duplicates := v_duplicates + 1;
      continue;
    end if;

    insert into public.contributions
      (chama_id, member_id, amount, contribution_date, notes, method, recorded_by)
    values
      (p_chama_id, v_member, v_amount, v_date, v_notes, 'import', auth.uid());

    v_inserted := v_inserted + 1;
  end loop;

  perform set_config('app.bulk_import', 'off', true);

  return query select v_inserted, v_duplicates;
end;
$function$;

CREATE OR REPLACE FUNCTION public.transfer_shares(p_chama_id uuid, p_from_member_id uuid, p_to_member_id uuid, p_amount numeric, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if not public.is_chama_treasurer(p_chama_id) then
    raise exception 'Only the treasurer can transfer shares';
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
$function$;

CREATE OR REPLACE FUNCTION public.chama_roster(p_chama_id uuid)
 RETURNS TABLE(id uuid, user_id uuid, role text, display_name text, phone text, has_account boolean, balance numeric, is_self boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_admin boolean;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_officer(p_chama_id);

  return query
  select
    m.id,
    m.user_id,
    m.role,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'Member') as display_name,
    case when v_is_admin or m.user_id = auth.uid() then coalesce(m.phone, p.phone) end as phone,
    (m.user_id is not null) as has_account,
    case when v_is_admin or m.user_id = auth.uid() then m.balance end as balance,
    (m.user_id = auth.uid()) as is_self
  from public.chama_members m
  left join public.profiles p on p.id = m.user_id
  where m.chama_id = p_chama_id and m.status = 'active'
  order by
    case m.role when 'chairperson' then 0 when 'treasurer' then 1
                when 'secretary' then 2 else 3 end,
    display_name;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chama_contributions(p_chama_id uuid)
 RETURNS TABLE(id uuid, member_id uuid, member_name text, amount numeric, contribution_date date, status text, notes text, reversal_reason text, reversed_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_admin boolean;
  v_self uuid;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_officer(p_chama_id);

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
$function$;

CREATE OR REPLACE FUNCTION public.chama_share_transfers(p_chama_id uuid)
 RETURNS TABLE(id uuid, amount numeric, reason text, created_at timestamp with time zone, from_member_id uuid, from_name text, to_member_id uuid, to_name text, performed_by_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_admin boolean;
  v_self uuid;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_officer(p_chama_id);
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
$function$;

CREATE OR REPLACE FUNCTION public.chama_archived_members(p_chama_id uuid)
 RETURNS TABLE(id uuid, display_name text, role text, status text, archived_at timestamp with time zone, archive_reason text, archive_note text, archived_balance numeric, balance numeric, archived_by_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_chama_officer(p_chama_id) then
    raise exception 'Only an officer of the chama can see the archive';
  end if;

  return query
  select
    m.id,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'Member'),
    m.role,
    m.status,
    m.archived_at,
    m.archive_reason,
    m.archive_note,
    m.archived_balance,
    m.balance,
    coalesce(nullif(trim(pb.full_name), ''), pb.email, 'An administrator')
  from public.chama_members m
  left join public.profiles p on p.id = m.user_id
  left join public.profiles pb on pb.id = m.archived_by
  where m.chama_id = p_chama_id
    and m.status in ('archived', 'removed')
  order by m.archived_at desc nulls last,
           coalesce(nullif(trim(p.full_name), ''), m.full_name);
end;
$function$;

CREATE OR REPLACE FUNCTION public.chama_loan_payoffs(p_chama_id uuid, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS TABLE(loan_id uuid, member_id uuid, member_name text, principal numeric, interest_rate numeric, interest_period text, issued_at timestamp with time zone, due_date date, status text, amount_repaid numeric, scheduled_total numeric, months_run numeric, months_scheduled numeric, interest_so_far numeric, settle_today numeric, saving numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_admin boolean;
  v_self uuid;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_officer(p_chama_id);
  select m.id into v_self from public.chama_members m
   where m.chama_id = p_chama_id and m.user_id = auth.uid();

  return query
  select
    l.id,
    l.member_id,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, 'Member'),
    l.principal,
    l.interest_rate,
    l.interest_period,
    l.issued_at,
    l.due_date,
    l.status,
    l.amount_repaid,
    l.total_due,
    least(public.loan_term_months(l.issued_at, greatest(p_as_of, l.issued_at::date)),
          public.loan_term_months(l.issued_at, l.due_date)),
    public.loan_term_months(l.issued_at, l.due_date),
    public.loan_accrued_total(l.principal, l.interest_rate, l.interest_period,
                              l.issued_at, l.due_date, p_as_of) - l.principal,
    greatest(public.loan_accrued_total(l.principal, l.interest_rate, l.interest_period,
                                       l.issued_at, l.due_date, p_as_of)
             - l.amount_repaid, 0),
    greatest(l.total_due - public.loan_accrued_total(l.principal, l.interest_rate,
             l.interest_period, l.issued_at, l.due_date, p_as_of), 0)
  from public.loans l
  join public.chama_members m on m.id = l.member_id
  left join public.profiles p on p.id = m.user_id
  where l.chama_id = p_chama_id
    and (v_is_admin or l.member_id = v_self)
  order by
    case l.status when 'active' then 0 when 'pending' then 1 else 2 end,
    l.issued_at desc nulls last;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loan_payoff(p_loan_id uuid, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS TABLE(principal numeric, interest_rate numeric, interest_period text, months_run numeric, months_scheduled numeric, interest_so_far numeric, payable_now numeric, amount_repaid numeric, settle_today numeric, scheduled_total numeric, saving numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l public.loans%rowtype;
  v_accrued numeric;
begin
  select * into l from public.loans where id = p_loan_id;
  if not found then
    raise exception 'That loan no longer exists';
  end if;

  if not public.is_chama_officer(l.chama_id)
     and not exists (
       select 1 from public.chama_members m
       where m.id = l.member_id and m.user_id = auth.uid()
     ) then
    raise exception 'Not allowed to see this loan';
  end if;

  v_accrued := public.loan_accrued_total(
    l.principal, l.interest_rate, l.interest_period, l.issued_at, l.due_date, p_as_of);

  return query select
    l.principal,
    l.interest_rate,
    l.interest_period,
    least(public.loan_term_months(l.issued_at, greatest(p_as_of, l.issued_at::date)),
          public.loan_term_months(l.issued_at, l.due_date)),
    public.loan_term_months(l.issued_at, l.due_date),
    v_accrued - l.principal,
    v_accrued,
    l.amount_repaid,
    greatest(v_accrued - l.amount_repaid, 0),
    l.total_due,
    greatest(l.total_due - v_accrued, 0);
end;
$function$;
