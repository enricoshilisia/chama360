-- Chama360 — single-chama-per-user limit (temporary simplification) and
-- backdated contributions.
--
-- Run after 0001-0003.

-- ============================================================
-- One chama per user, for now. Multi-chama membership is deferred to a
-- later version (per product decision) — enforced here so it can't be
-- bypassed by calling the RPCs directly, not just hidden in the UI.
-- ============================================================
create or replace function public.create_chama(p_name text, p_description text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_code text;
begin
  if exists (
    select 1 from public.chama_members
    where user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'You can only be part of one chama for now';
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into public.chamas (name, description, invite_code, created_by)
  values (p_name, p_description, v_code, auth.uid())
  returning id into v_chama_id;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'chairperson', 'active');

  return v_chama_id;
end;
$$;

create or replace function public.join_chama_by_code(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_member_id uuid;
begin
  if exists (
    select 1 from public.chama_members
    where user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'You can only be part of one chama for now';
  end if;

  select id into v_chama_id from public.chamas where invite_code = p_invite_code;

  if v_chama_id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'member', 'active')
  on conflict (chama_id, user_id) do update set status = 'active'
  returning id into v_member_id;

  return v_chama_id;
end;
$$;

-- ============================================================
-- Backdated contributions: let the chairperson pass an explicit date
-- (contributions.contribution_date already existed and defaulted to
-- current_date — this just means the client can now override it).
-- No schema change needed, only documenting the intent here since it's
-- easy to miss: RLS policy "contributions_insert_member" already allows
-- an admin to set any column on their own insert, contribution_date
-- included.
-- ============================================================
