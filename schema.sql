-- Lược đồ Supabase cho "ACQ Smarthome · Sổ việc"
-- Chạy toàn bộ file này trong Supabase → SQL Editor → New query → Run.

create extension if not exists pgcrypto;

-- Hồ sơ người dùng: id trùng với auth.users.id
create table if not exists users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  phone text default '',
  email text default '',
  role text not null default 'staff' check (role in ('owner','staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Khi có tài khoản auth mới → tự tạo hồ sơ (vai trò nhân viên; chủ sửa lại sau)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    insert into public.users (id, email, name)
    values (new.id, coalesce(new.email,''), coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email,''),'@',1)))
    on conflict (id) do nothing;
  exception when others then
    raise warning 'handle_new_user: %', sqlerrm;
  end;
  return new;
end $$;
alter function public.handle_new_user() owner to postgres;
grant usage on schema public to supabase_auth_admin;
grant insert, select on public.users to supabase_auth_admin;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create table if not exists settings (
  id text primary key default 'main',
  shop_name text default 'Cửa hàng', address text default '', phone text default '',
  created_at timestamptz not null default now()
);
insert into settings (id) values ('main') on conflict do nothing;

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  name text not null, phone text default '', address text default '', note text default '',
  sites jsonb default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists jobs (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  customer_id uuid references customers(id),
  type text default 'sua', title text not null, description text default '',
  assignee_id uuid references users(id),
  status text not null default 'moi' check (status in ('moi','dang_lam','cho_vat_tu','hoan_thanh','huy')),
  priority text default 'vua',
  due_at timestamptz, done_at timestamptz,
  quote numeric default 0,
  mode text default 'onsite', est numeric, progress integer default 0, seq integer,
  address text default '', site_lat double precision, site_lng double precision, site_auto boolean default false,
  lat double precision, lng double precision,
  created_by uuid references users(id),
  created_at timestamptz not null default now()
);

create table if not exists job_logs (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  user_id uuid references users(id),
  type text default 'note', text text default '', photo text,
  lat double precision, lng double precision, acc numeric,
  flag text, remote boolean default false, closed_by uuid references users(id),
  created_at timestamptz not null default now()
);

create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  name text not null, sku text default '', unit text default 'cái',
  qty numeric default 0, min_qty numeric default 0,
  cost numeric default 0, price numeric default 0,
  created_at timestamptz not null default now()
);

create table if not exists job_items (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  item_id uuid references items(id),
  qty numeric default 1, unit_price numeric default 0,
  created_at timestamptz not null default now()
);

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  user_id uuid references users(id),
  "desc" text default '', amount numeric default 0,
  paid boolean default false, paid_at timestamptz, receipt text,
  created_at timestamptz not null default now()
);

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  amount numeric default 0, method text default 'tien_mat', note text default '',
  user_id uuid references users(id),
  created_at timestamptz not null default now()
);

create table if not exists acceptances (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  content text default '', note text default '', customer_name text default '', signer text default '',
  total numeric default 0, signature text, signed_at timestamptz,
  mode text default 'sign', remote boolean default false, photos jsonb, chat_photo text,
  extras jsonb, extras_priced boolean default false, flags jsonb, delivery boolean default false,
  lat double precision, lng double precision, acc numeric,
  user_id uuid references users(id),
  created_at timestamptz not null default now()
);

-- Hàm phân quyền dùng chung
create or replace function is_owner() returns boolean language sql stable security definer as $$
  select coalesce((select role = 'owner' and active from users where id = auth.uid()), false)
$$;
create or replace function is_member() returns boolean language sql stable security definer as $$
  select coalesce((select active from users where id = auth.uid()), false)
$$;

-- Nhân viên không thấy giá nên khi xuất vật tư, giá bán được điền tự động từ kho
create or replace function fill_job_item_price() returns trigger language plpgsql security definer as $$
begin
  if new.unit_price is null or new.unit_price = 0 then
    select price into new.unit_price from items where id = new.item_id;
  end if;
  return new;
end $$;
drop trigger if exists job_items_price on job_items;
create trigger job_items_price before insert on job_items for each row execute function fill_job_item_price();

-- ===== Ràng buộc chống trốn việc (thực thi ở CSDL, giao diện không vượt được) =====
-- KTV không được tự đặt Hoàn thành/Hủy; Hoàn thành chỉ hợp lệ khi đã có phiếu xác nhận
create or replace function guard_job_status() returns trigger language plpgsql security definer as $$
begin
  if not is_owner() and new.status is distinct from old.status and new.status in ('hoan_thanh','huy') then
    if new.status = 'huy' then raise exception 'Chỉ chủ mới được hủy việc'; end if;
    if not exists (select 1 from acceptances where job_id = new.id) then raise exception 'Hoàn thành chỉ qua phiếu xác nhận'; end if;
  end if;
  return new;
end $$;
drop trigger if exists jobs_guard_status on jobs;
create trigger jobs_guard_status before update on jobs for each row execute function guard_job_status();

-- Phiếu xác nhận chỉ lập được khi người lập đã có ca Bắt đầu trên việc đó (chủ được miễn)
create or replace function guard_acceptance() returns trigger language plpgsql security definer as $$
begin
  if not is_owner() then
    if (select mode from jobs where id = new.job_id) = 'remote' then
      if not exists (select 1 from job_logs where job_id = new.job_id and user_id = auth.uid() and type = 'checkin') then
        raise exception 'Phải bấm Bắt đầu trên việc trước khi lập phiếu'; end if;
    elsif (select mode from jobs where id = new.job_id) = 'onsite' then
      -- phải đang có mặt: mốc cuối cùng của KTV trên việc này là checkin tại chỗ (không phải từ xa)
      if not exists (select 1 from job_logs l where l.job_id = new.job_id and l.user_id = auth.uid() and l.type = 'checkin' and coalesce(l.remote,false) = false
                     and l.created_at >= coalesce((select max(created_at) from job_logs where job_id = new.job_id and user_id = auth.uid() and type = 'checkout'), '-infinity')) then
        raise exception 'Phải đang có mặt tại công trình (bấm Bắt đầu tại công trình) mới lập phiếu được'; end if;
    end if;
  end if;
  new.user_id := auth.uid();
  return new;
end $$;
drop trigger if exists acceptances_guard on acceptances;
create trigger acceptances_guard before insert on acceptances for each row execute function guard_acceptance();

-- Nhật ký / check-in luôn ghi đúng người đang đăng nhập (KTV không thể ghi hộ)
create or replace function stamp_log_user() returns trigger language plpgsql security definer as $$
begin
  if not is_owner() then new.user_id := auth.uid(); end if;
  return new;
end $$;
drop trigger if exists job_logs_stamp on job_logs;
create trigger job_logs_stamp before insert on job_logs for each row execute function stamp_log_user();

-- ===== Phân quyền (Row Level Security) =====

-- Nhân viên: xem kho nhưng không thấy giá vốn / giá bán
create or replace view items_staff with (security_invoker = off) as
  select id, name, sku, unit, qty, min_qty, created_at from items;
grant select on items_staff to authenticated;

alter table users enable row level security;
alter table settings enable row level security;
alter table customers enable row level security;
alter table jobs enable row level security;
alter table job_logs enable row level security;
alter table items enable row level security;
alter table job_items enable row level security;
alter table expenses enable row level security;
alter table payments enable row level security;
alter table acceptances enable row level security;

-- users: mọi thành viên xem danh sách; chỉ chủ sửa
drop policy if exists users_select on users; create policy users_select on users for select using (is_member() or id = auth.uid());
drop policy if exists users_owner on users; create policy users_owner on users for update using (is_owner());
drop policy if exists users_auth_admin on users; create policy users_auth_admin on users for insert to supabase_auth_admin with check (true);

-- settings: xem chung, chủ sửa
drop policy if exists settings_select on settings; create policy settings_select on settings for select using (is_member());
drop policy if exists settings_owner on settings; create policy settings_owner on settings for all using (is_owner());

-- customers, jobs, job_logs, job_items, payments, acceptances: thành viên đọc/ghi
do $$ declare t text; begin
  foreach t in array array['customers','job_items','payments'] loop
    execute format('drop policy if exists %I_member on %I', t, t);
    execute format('create policy %I_member on %I for all using (is_member()) with check (is_member())', t, t);
  end loop;
end $$;

-- jobs: thành viên đọc và cập nhật (trạng thái, tiến độ, phân công tự nhận); chỉ chủ tạo mới / xóa
-- KTV chỉ thấy và cập nhật việc được giao cho mình
drop policy if exists jobs_select on jobs; create policy jobs_select on jobs for select using (is_owner() or assignee_id = auth.uid());
drop policy if exists jobs_update on jobs; create policy jobs_update on jobs for update using (is_owner() or assignee_id = auth.uid()) with check (is_owner() or assignee_id = auth.uid());
drop policy if exists jobs_owner on jobs; create policy jobs_owner on jobs for all using (is_owner()) with check (is_owner());

-- job_logs: thành viên đọc và thêm; không ai ngoài chủ được sửa/xóa (nhật ký, check-in là bằng chứng)
drop policy if exists logs_select on job_logs; create policy logs_select on job_logs for select using (is_member());
drop policy if exists logs_insert on job_logs; create policy logs_insert on job_logs for insert with check (is_member());
drop policy if exists logs_owner on job_logs; create policy logs_owner on job_logs for all using (is_owner()) with check (is_owner());
-- acceptances: thành viên đọc và thêm; chỉ chủ sửa (định giá phát sinh) / xóa
drop policy if exists acc_select on acceptances; create policy acc_select on acceptances for select using (is_member());
drop policy if exists acc_insert on acceptances; create policy acc_insert on acceptances for insert with check (is_member());
drop policy if exists acc_owner on acceptances; create policy acc_owner on acceptances for all using (is_owner()) with check (is_owner());

-- items: chủ toàn quyền; nhân viên được cập nhật số lượng (xuất vật tư, kiểm kê) nhưng chỉ đọc qua items_staff
drop policy if exists items_owner on items; create policy items_owner on items for all using (is_owner()) with check (is_owner());
drop policy if exists items_staff_update on items; create policy items_staff_update on items for update using (is_member()) with check (is_member());

-- expenses: nhân viên chỉ thấy/ghi khoản của mình; chủ thấy tất cả và đánh dấu đã thanh toán
drop policy if exists exp_owner on expenses; create policy exp_owner on expenses for all using (is_owner()) with check (is_owner());
drop policy if exists exp_self_select on expenses; create policy exp_self_select on expenses for select using (user_id = auth.uid());
drop policy if exists exp_self_insert on expenses; create policy exp_self_insert on expenses for insert with check (user_id = auth.uid() and is_member());

-- Sau khi chạy: vào Authentication → Users → tạo tài khoản chủ, rồi chạy:
-- update users set role='owner', name='Tên chủ cửa hàng' where email='email-cua-chu@...';

-- ===== Đồng bộ thời gian thực (chủ ↔ KTV thấy thay đổi ngay) =====
do $$ declare t text; begin
  foreach t in array array['jobs','job_logs','acceptances','payments','expenses','job_items','items','customers','users','settings'] loop
    begin execute format('alter publication supabase_realtime add table %I', t); exception when duplicate_object then null; end;
  end loop;
end $$;

-- ===== Thông báo trong app + thông báo đẩy =====
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,     -- người nhận
  from_id uuid references users(id),
  title text not null, body text default '', job_id uuid references jobs(id) on delete set null,
  kind text default 'info', read boolean default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on notifications(user_id, read, created_at desc);
alter table notifications enable row level security;
drop policy if exists notif_select on notifications; create policy notif_select on notifications for select using (user_id = auth.uid());
drop policy if exists notif_insert on notifications; create policy notif_insert on notifications for insert with check (is_member());
drop policy if exists notif_update on notifications; create policy notif_update on notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists push_subscriptions (
  endpoint text primary key,
  user_id uuid references users(id) on delete cascade,
  keys jsonb not null, ua text default '',
  created_at timestamptz not null default now()
);
alter table push_subscriptions enable row level security;
drop policy if exists push_own on push_subscriptions; create policy push_own on push_subscriptions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

do $$ begin execute 'alter publication supabase_realtime add table notifications'; exception when duplicate_object then null; end $$;

-- Gửi Web Push khi có thông báo mới: trigger gọi Edge Function qua pg_net.
-- Thay 2 chỗ qzdhpgxllrehyggfwsor và sb_publishable_Lcji-dafAWQ1sfLzb4PzLg_VjEAJftR bằng giá trị của dự án (Project Settings → API).
create extension if not exists pg_net;
create or replace function notify_push() returns trigger language plpgsql security definer as $$
begin
  perform net.http_post(
    url := 'https://qzdhpgxllrehyggfwsor.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_Lcji-dafAWQ1sfLzb4PzLg_VjEAJftR'),
    body := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
end $$;
drop trigger if exists notifications_push on notifications;
create trigger notifications_push after insert on notifications for each row execute function notify_push();

-- ===== Gán vai trò chủ (chạy sau khi đã tạo user trong Authentication) =====
-- update users set role='owner', name='ACQ Smarthome' where email='<email-chủ>';
