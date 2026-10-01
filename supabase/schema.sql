-- QuoteSnap database schema
-- Designed to live in the same Supabase project as DetailFlow.
-- QuoteSnap owns only qs_* tables and policies.
-- Supabase Auth (auth.users) is shared, but authorization is app-specific.

create extension if not exists pgcrypto;

-- ============================================================
-- Helpers
-- ============================================================

create or replace function public.qs_is_member(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.qs_organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
  );
$$;

create or replace function public.qs_has_role(
  p_organization_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.qs_organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.role = any(p_roles)
  );
$$;

create or replace function public.qs_is_org_owner(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.qs_organizations o
    where o.id = p_organization_id
      and o.owner_id = auth.uid()
  );
$$;

-- Keep organization ownership and membership in sync.
create or replace function public.qs_add_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.qs_organization_members (
    organization_id,
    user_id,
    role
  )
  values (
    new.id,
    new.owner_id,
    'owner'
  )
  on conflict (organization_id, user_id)
  do update set role = 'owner';

  return new;
end;
$$;

-- Prevent users from changing security-sensitive ownership fields.
create or replace function public.qs_protect_org_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.owner_id <> old.owner_id then
    raise exception 'organization owner cannot be changed';
  end if;

  return new;
end;
$$;

-- ============================================================
-- Organizations / memberships
-- ============================================================

create table if not exists public.qs_organizations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null check (length(trim(name)) between 1 and 120),
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text,
  email text,
  phone text,
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  tax_rate numeric(7,4) not null default 0
    check (tax_rate >= 0 and tax_rate <= 100),
  logo_url text,
  brand_color text,
  plan text not null default 'free'
    check (plan in ('free','pro','business')),
  subscription_status text not null default 'inactive'
    check (subscription_status in ('inactive','trialing','active','past_due','canceled','incomplete')),
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  trial_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.qs_organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.qs_organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','manager','member','viewer')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create index if not exists qs_org_owner_idx
  on public.qs_organizations(owner_id);

create index if not exists qs_members_user_org_idx
  on public.qs_organization_members(user_id, organization_id);

create index if not exists qs_members_org_role_idx
  on public.qs_organization_members(organization_id, role);

drop trigger if exists qs_organization_owner_membership on public.qs_organizations;
create trigger qs_organization_owner_membership
after insert on public.qs_organizations
for each row execute function public.qs_add_owner_membership();

drop trigger if exists qs_protect_org_owner on public.qs_organizations;
create trigger qs_protect_org_owner
before update on public.qs_organizations
for each row execute function public.qs_protect_org_owner();

-- ============================================================
-- Customers
-- ============================================================

create table if not exists public.qs_customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.qs_organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  email text,
  phone text,
  company_name text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists qs_customers_org_idx
  on public.qs_customers(organization_id);

create index if not exists qs_customers_org_email_idx
  on public.qs_customers(organization_id, lower(email));

-- ============================================================
-- Services
-- ============================================================

create table if not exists public.qs_services (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.qs_organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  description text,
  unit text not null default 'item',
  default_price_cents bigint not null default 0
    check (default_price_cents >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists qs_services_org_active_idx
  on public.qs_services(organization_id, active);

-- ============================================================
-- Quotes
-- ============================================================

create table if not exists public.qs_quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.qs_organizations(id) on delete cascade,
  customer_id uuid references public.qs_customers(id) on delete set null,
  quote_number text not null,
  status text not null default 'draft'
    check (status in ('draft','sent','viewed','accepted','declined','expired','canceled')),
  title text,
  notes text,
  subtotal_cents bigint not null default 0 check (subtotal_cents >= 0),
  discount_cents bigint not null default 0 check (discount_cents >= 0),
  tax_cents bigint not null default 0 check (tax_cents >= 0),
  total_cents bigint not null default 0 check (total_cents >= 0),
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  valid_until date,
  public_token_hash text unique,
  public_token_expires_at timestamptz,
  accepted_at timestamptz,
  declined_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, quote_number)
);

create index if not exists qs_quotes_org_idx
  on public.qs_quotes(organization_id);

create index if not exists qs_quotes_org_status_idx
  on public.qs_quotes(organization_id, status);

create index if not exists qs_quotes_customer_idx
  on public.qs_quotes(customer_id);

create index if not exists qs_quotes_created_at_idx
  on public.qs_quotes(organization_id, created_at desc);

create unique index if not exists qs_quotes_public_token_hash_idx
  on public.qs_quotes(public_token_hash)
  where public_token_hash is not null;

-- ============================================================
-- Quote line items
-- ============================================================

create table if not exists public.qs_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.qs_quotes(id) on delete cascade,
  service_id uuid references public.qs_services(id) on delete set null,
  description text not null check (length(trim(description)) between 1 and 500),
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  unit_price_cents bigint not null default 0 check (unit_price_cents >= 0),
  line_total_cents bigint not null default 0 check (line_total_cents >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists qs_quote_items_quote_idx
  on public.qs_quote_items(quote_id, sort_order);

-- ============================================================
-- Quote events / audit trail
-- ============================================================

create table if not exists public.qs_quote_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.qs_organizations(id) on delete cascade,
  quote_id uuid references public.qs_quotes(id) on delete cascade,
  event_type text not null
    check (event_type in (
      'created','updated','sent','viewed','accepted','declined',
      'expired','canceled','payment_started','payment_completed'
    )),
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists qs_quote_events_quote_idx
  on public.qs_quote_events(quote_id, created_at desc);

create index if not exists qs_quote_events_org_idx
  on public.qs_quote_events(organization_id, created_at desc);

create table if not exists public.qs_audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid references public.qs_organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists qs_audit_org_created_idx
  on public.qs_audit_logs(organization_id, created_at desc);

create index if not exists qs_audit_entity_idx
  on public.qs_audit_logs(entity_type, entity_id);

-- ============================================================
-- Updated-at helper
-- ============================================================

create or replace function public.qs_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'qs_organizations',
    'qs_customers',
    'qs_services',
    'qs_quotes'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      t || '_updated_at',
      t
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.qs_set_updated_at()',
      t || '_updated_at',
      t
    );
  end loop;
end $$;

-- ============================================================
-- RLS
-- ============================================================

alter table public.qs_organizations enable row level security;
alter table public.qs_organization_members enable row level security;
alter table public.qs_customers enable row level security;
alter table public.qs_services enable row level security;
alter table public.qs_quotes enable row level security;
alter table public.qs_quote_items enable row level security;
alter table public.qs_quote_events enable row level security;
alter table public.qs_audit_logs enable row level security;

-- Organizations
drop policy if exists qs_org_select on public.qs_organizations;
create policy qs_org_select
on public.qs_organizations
for select
to authenticated
using (public.qs_is_member(id));

drop policy if exists qs_org_insert on public.qs_organizations;
create policy qs_org_insert
on public.qs_organizations
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists qs_org_update on public.qs_organizations;
create policy qs_org_update
on public.qs_organizations
for update
to authenticated
using (public.qs_has_role(id, array['owner','admin']))
with check (public.qs_has_role(id, array['owner','admin']));

-- No client-side delete of organizations.
-- Deletion should be a controlled server-side/admin operation.

-- Memberships
drop policy if exists qs_members_select on public.qs_organization_members;
create policy qs_members_select
on public.qs_organization_members
for select
to authenticated
using (public.qs_is_member(organization_id));

drop policy if exists qs_members_insert on public.qs_organization_members;
create policy qs_members_insert
on public.qs_organization_members
for insert
to authenticated
with check (
  public.qs_has_role(organization_id, array['owner','admin'])
);

drop policy if exists qs_members_update on public.qs_organization_members;
create policy qs_members_update
on public.qs_organization_members
for update
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin']))
with check (
  public.qs_has_role(organization_id, array['owner','admin'])
  and role <> 'owner'
);

drop policy if exists qs_members_delete on public.qs_organization_members;
create policy qs_members_delete
on public.qs_organization_members
for delete
to authenticated
using (
  public.qs_has_role(organization_id, array['owner','admin'])
  and role <> 'owner'
);

-- Customers
drop policy if exists qs_customers_select on public.qs_customers;
create policy qs_customers_select
on public.qs_customers
for select
to authenticated
using (public.qs_is_member(organization_id));

drop policy if exists qs_customers_insert on public.qs_customers;
create policy qs_customers_insert
on public.qs_customers
for insert
to authenticated
with check (
  public.qs_has_role(organization_id, array['owner','admin','manager','member'])
);

drop policy if exists qs_customers_update on public.qs_customers;
create policy qs_customers_update
on public.qs_customers
for update
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager','member']))
with check (public.qs_has_role(organization_id, array['owner','admin','manager','member']));

drop policy if exists qs_customers_delete on public.qs_customers;
create policy qs_customers_delete
on public.qs_customers
for delete
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager']));

-- Services
drop policy if exists qs_services_select on public.qs_services;
create policy qs_services_select
on public.qs_services
for select
to authenticated
using (public.qs_is_member(organization_id));

drop policy if exists qs_services_insert on public.qs_services;
create policy qs_services_insert
on public.qs_services
for insert
to authenticated
with check (public.qs_has_role(organization_id, array['owner','admin','manager']));

drop policy if exists qs_services_update on public.qs_services;
create policy qs_services_update
on public.qs_services
for update
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager']))
with check (public.qs_has_role(organization_id, array['owner','admin','manager']));

drop policy if exists qs_services_delete on public.qs_services;
create policy qs_services_delete
on public.qs_services
for delete
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager']));

-- Quotes
drop policy if exists qs_quotes_select on public.qs_quotes;
create policy qs_quotes_select
on public.qs_quotes
for select
to authenticated
using (public.qs_is_member(organization_id));

drop policy if exists qs_quotes_insert on public.qs_quotes;
create policy qs_quotes_insert
on public.qs_quotes
for insert
to authenticated
with check (
  public.qs_has_role(organization_id, array['owner','admin','manager','member'])
  and created_by = auth.uid()
);

drop policy if exists qs_quotes_update on public.qs_quotes;
create policy qs_quotes_update
on public.qs_quotes
for update
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager','member']))
with check (public.qs_has_role(organization_id, array['owner','admin','manager','member']));

drop policy if exists qs_quotes_delete on public.qs_quotes;
create policy qs_quotes_delete
on public.qs_quotes
for delete
to authenticated
using (public.qs_has_role(organization_id, array['owner','admin','manager']));

-- Quote items: authorization is derived from the quote's organization.
drop policy if exists qs_quote_items_select on public.qs_quote_items;
create policy qs_quote_items_select
on public.qs_quote_items
for select
to authenticated
using (
  exists (
    select 1
    from public.qs_quotes q
    where q.id = quote_id
      and public.qs_is_member(q.organization_id)
  )
);

drop policy if exists qs_quote_items_insert on public.qs_quote_items;
create policy qs_quote_items_insert
on public.qs_quote_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.qs_quotes q
    where q.id = quote_id
      and public.qs_has_role(q.organization_id, array['owner','admin','manager','member'])
  )
);

drop policy if exists qs_quote_items_update on public.qs_quote_items;
create policy qs_quote_items_update
on public.qs_quote_items
for update
to authenticated
using (
  exists (
    select 1
    from public.qs_quotes q
    where q.id = quote_id
      and public.qs_has_role(q.organization_id, array['owner','admin','manager','member'])
  )
)
with check (
  exists (
    select 1
    from public.qs_quotes q
    where q.id = quote_id
      and public.qs_has_role(q.organization_id, array['owner','admin','manager','member'])
  )
);

drop policy if exists qs_quote_items_delete on public.qs_quote_items;
create policy qs_quote_items_delete
on public.qs_quote_items
for delete
to authenticated
using (
  exists (
    select 1
    from public.qs_quotes q
    where q.id = quote_id
      and public.qs_has_role(q.organization_id, array['owner','admin','manager'])
  )
);

-- Quote events
drop policy if exists qs_quote_events_select on public.qs_quote_events;
create policy qs_quote_events_select
on public.qs_quote_events
for select
to authenticated
using (public.qs_is_member(organization_id));

drop policy if exists qs_quote_events_insert on public.qs_quote_events;
create policy qs_quote_events_insert
on public.qs_quote_events
for insert
to authenticated
with check (
  public.qs_is_member(organization_id)
  and (actor_user_id is null or actor_user_id = auth.uid())
);

-- Events are append-only from the client.
-- No update/delete policies.

-- Audit logs
drop policy if exists qs_audit_select on public.qs_audit_logs;
create policy qs_audit_select
on public.qs_audit_logs
for select
to authenticated
using (
  public.qs_has_role(organization_id, array['owner','admin'])
);

-- No direct client insert/update/delete policies.
-- Audit records should be written by trusted server-side code.

-- ============================================================
-- Cross-organization integrity for foreign keys
-- ============================================================

create or replace function public.qs_validate_customer_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_id is not null and not exists (
    select 1
    from public.qs_customers c
    where c.id = new.customer_id
      and c.organization_id = new.organization_id
  ) then
    raise exception 'customer does not belong to quote organization';
  end if;

  return new;
end;
$$;

drop trigger if exists qs_validate_quote_customer_org on public.qs_quotes;
create trigger qs_validate_quote_customer_org
before insert or update on public.qs_quotes
for each row execute function public.qs_validate_customer_org();

create or replace function public.qs_validate_service_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  quote_org uuid;
begin
  select organization_id into quote_org
  from public.qs_quotes
  where id = new.quote_id;

  if quote_org is null then
    raise exception 'quote does not exist';
  end if;

  if new.service_id is not null and not exists (
    select 1
    from public.qs_services s
    where s.id = new.service_id
      and s.organization_id = quote_org
  ) then
    raise exception 'service does not belong to quote organization';
  end if;

  return new;
end;
$$;

drop trigger if exists qs_validate_quote_item_service_org on public.qs_quote_items;
create trigger qs_validate_quote_item_service_org
before insert or update on public.qs_quote_items
for each row execute function public.qs_validate_service_org();

-- ============================================================
-- Safe public quote access
-- ============================================================

-- Public quote pages must NOT expose the raw token or bypass RLS by
-- selecting the table directly. The application should call this RPC
-- with the raw token it received in the URL.
create or replace function public.qs_get_public_quote(
  p_token text
)
returns table (
  quote_id uuid,
  organization_id uuid,
  organization_name text,
  quote_number text,
  status text,
  title text,
  notes text,
  subtotal_cents bigint,
  discount_cents bigint,
  tax_cents bigint,
  total_cents bigint,
  currency text,
  valid_until date
)
language sql
stable
security definer
set search_path = public
as $$
  select
    q.id,
    q.organization_id,
    o.name,
    q.quote_number,
    q.status,
    q.title,
    q.notes,
    q.subtotal_cents,
    q.discount_cents,
    q.tax_cents,
    q.total_cents,
    q.currency,
    q.valid_until
  from public.qs_quotes q
  join public.qs_organizations o on o.id = q.organization_id
  where q.public_token_hash = encode(digest(p_token, 'sha256'), 'hex')
    and (
      q.public_token_expires_at is null
      or q.public_token_expires_at > now()
    )
    and q.status not in ('canceled','expired');
$$;

revoke all on function public.qs_get_public_quote(text) from public;
grant execute on function public.qs_get_public_quote(text) to anon, authenticated;

-- ============================================================
-- Grants
-- ============================================================

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select, insert, update, delete on
  public.qs_organizations,
  public.qs_organization_members,
  public.qs_customers,
  public.qs_services,
  public.qs_quotes,
  public.qs_quote_items,
  public.qs_quote_events
to authenticated;

grant select on public.qs_audit_logs to authenticated;

-- Identity access for app users.
grant usage on schema public to anon, authenticated;
