-- Who may change the money, and who may see it.
--
-- Until now one predicate did both jobs: is_chama_admin, meaning
-- chairperson or treasurer, decided every write and every read of
-- anyone else's figures. That conflated three different questions, and
-- it meant the secretary — who in most chamas keeps the register — could
-- see no more than an ordinary member, while the chairperson could move
-- money they are not supposed to touch.
--
-- Three questions, three answers:
--
--   is_chama_treasurer  may change money. One person. Contributions,
--                       loans, repayments, reversals, transfers, imports.
--   is_chama_admin      may manage the roster. Chairperson or treasurer:
--                       members, logins, roles, archiving. Deliberately
--                       two people, so a chama can always appoint a new
--                       treasurer and can never lock itself out.
--   is_chama_officer    may see everything, read-only. Chairperson,
--                       treasurer or secretary.
--
-- is_chama_admin keeps its definition and simply stops gating money.

create or replace function public.is_chama_treasurer(p_chama_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.chama_role(p_chama_id) = 'treasurer';
$$;

create or replace function public.is_chama_officer(p_chama_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.chama_role(p_chama_id) in ('chairperson', 'treasurer', 'secretary');
$$;

grant execute on function public.is_chama_treasurer(uuid) to authenticated;
grant execute on function public.is_chama_officer(uuid) to authenticated;

-- ------------------------------------------------ reads: any officer

drop policy if exists chama_members_select_own_or_admin on public.chama_members;
create policy chama_members_select_own_or_admin on public.chama_members
  for select using (user_id = auth.uid() or public.is_chama_officer(chama_id));

drop policy if exists contributions_select_own_or_admin on public.contributions;
create policy contributions_select_own_or_admin on public.contributions
  for select using (
    public.is_chama_officer(chama_id)
    or member_id in (select cm.id from public.chama_members cm
                     where cm.chama_id = contributions.chama_id and cm.user_id = auth.uid())
  );

drop policy if exists transactions_select_own_or_admin on public.transactions;
create policy transactions_select_own_or_admin on public.transactions
  for select using (
    public.is_chama_officer(chama_id)
    or member_id in (select cm.id from public.chama_members cm
                     where cm.chama_id = transactions.chama_id and cm.user_id = auth.uid())
  );

drop policy if exists loans_select_own_or_admin on public.loans;
create policy loans_select_own_or_admin on public.loans
  for select using (
    public.is_chama_officer(chama_id)
    or member_id in (select cm.id from public.chama_members cm
                     where cm.chama_id = loans.chama_id and cm.user_id = auth.uid())
  );

drop policy if exists loan_repayments_select_own_or_admin on public.loan_repayments;
create policy loan_repayments_select_own_or_admin on public.loan_repayments
  for select using (
    exists (select 1 from public.loans l
            where l.id = loan_repayments.loan_id
              and (public.is_chama_officer(l.chama_id)
                   or l.member_id in (select cm.id from public.chama_members cm
                                      where cm.chama_id = l.chama_id
                                        and cm.user_id = auth.uid())))
  );

drop policy if exists share_transfers_select on public.share_transfers;
create policy share_transfers_select on public.share_transfers
  for select using (
    public.is_chama_officer(chama_id)
    or from_member_id in (select cm.id from public.chama_members cm
                          where cm.chama_id = share_transfers.chama_id and cm.user_id = auth.uid())
    or to_member_id in (select cm.id from public.chama_members cm
                        where cm.chama_id = share_transfers.chama_id and cm.user_id = auth.uid())
  );

-- -------------------------------------------- money writes: treasurer

drop policy if exists contributions_insert_member on public.contributions;
create policy contributions_insert_member on public.contributions
  for insert with check (
    public.is_chama_member(chama_id)
    and public.is_chama_active(chama_id)
    and (
      public.is_chama_treasurer(chama_id)
      or member_id in (select cm.id from public.chama_members cm
                       where cm.chama_id = contributions.chama_id and cm.user_id = auth.uid())
    )
  );

drop policy if exists loans_insert_member on public.loans;
create policy loans_insert_member on public.loans
  for insert with check (
    public.is_chama_member(chama_id)
    and public.is_chama_active(chama_id)
    and (
      public.is_chama_treasurer(chama_id)
      or (status = 'pending'
          and member_id in (select cm.id from public.chama_members cm
                            where cm.chama_id = loans.chama_id and cm.user_id = auth.uid()))
    )
  );

drop policy if exists loans_admin_update on public.loans;
create policy loans_admin_update on public.loans
  for update using (public.is_chama_treasurer(chama_id));

drop policy if exists loan_repayments_admin_insert on public.loan_repayments;
create policy loan_repayments_admin_insert on public.loan_repayments
  for insert with check (
    exists (select 1 from public.loans l
            where l.id = loan_repayments.loan_id
              and public.is_chama_treasurer(l.chama_id))
  );

-- ------------------------------------------- the money functions too

create or replace function public.guard_treasurer(p_chama_id uuid, p_action text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_chama_treasurer(p_chama_id) then
    raise exception 'Only the treasurer can %', p_action;
  end if;
end;
$$;

grant execute on function public.guard_treasurer(uuid, text) to authenticated;
