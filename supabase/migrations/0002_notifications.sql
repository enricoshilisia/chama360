-- Chama360 — in-app notifications
-- Run after 0001_init_schema.sql.

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  chama_id    uuid references public.chamas(id) on delete cascade,
  title       text not null,
  body        text,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update using (user_id = auth.uid());

create index if not exists idx_notifications_user on public.notifications(user_id, created_at desc);

-- Notify every active member of a chama except the actor. Called from
-- triggers below (contributions, loans) — keeps notification fan-out in
-- one place instead of duplicating it per feature.
create or replace function public.notify_chama_members(
  p_chama_id uuid, p_title text, p_body text, p_exclude_user uuid default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.notifications (user_id, chama_id, title, body)
  select cm.user_id, p_chama_id, p_title, p_body
  from public.chama_members cm
  where cm.chama_id = p_chama_id
    and cm.status = 'active'
    and (p_exclude_user is null or cm.user_id <> p_exclude_user);
end;
$$;

create or replace function public.handle_contribution_notification()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if new.status = 'completed' then
    select p.full_name into v_name
    from public.chama_members cm join public.profiles p on p.id = cm.user_id
    where cm.id = new.member_id;

    perform public.notify_chama_members(
      new.chama_id,
      'New contribution',
      coalesce(v_name, 'A member') || ' contributed ' || new.amount::text,
      new.recorded_by
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_contribution_notify on public.contributions;
create trigger on_contribution_notify
  after insert on public.contributions
  for each row execute procedure public.handle_contribution_notification();

create or replace function public.handle_loan_status_notification()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if new.status is distinct from old.status then
    select user_id into v_user_id from public.chama_members where id = new.member_id;

    insert into public.notifications (user_id, chama_id, title, body)
    values (
      v_user_id,
      new.chama_id,
      'Loan update',
      'Your loan request is now: ' || new.status
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_loan_status_notify on public.loans;
create trigger on_loan_status_notify
  after update on public.loans
  for each row execute procedure public.handle_loan_status_notification();
