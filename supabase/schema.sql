-- =====================================================================
-- Daily Report LKA - Skema database Supabase (project TERPISAH dari NKA)
-- Jalankan SELURUH file ini sekali: SQL Editor -> New query -> tempel -> Run.
-- Aman dijalankan ulang (idempotent). Setelah itu jalankan supabase/data_awal.sql.
--
-- Jabatan: mt (Manajer Trainer), trainer, sales, pc (Product Consultant)
--   MT      : semua area
--   Trainer : area milik Sales yang ia pegang (tabel trainer_sales)
--   Sales   : 1 area (areas.sales_id)
--   PC      : 1 toko (profiles.store_id); 1 toko bisa punya beberapa PC
-- Stok & MS Allbrand per TOKO. Penjualan, cek limit, laporan per PC.
-- Produk & harga per AREA. KPI & insentif per WILAYAH TRAINER.
-- Semua tanggal & batas waktu memakai WIB (Asia/Jakarta).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TABEL MASTER
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  role text not null check (role in ('mt', 'manajer', 'trainer', 'sales', 'pc')),   -- manajer = Manajer LKA (lihat saja)
  store_id int,                                 -- wajib untuk PC (FK ditambah setelah tabel stores)
  email text not null unique,
  auth_uid uuid unique references auth.users(id) on delete set null,
  aktif boolean not null default true,
  last_seen timestamptz,
  last_login timestamptz,
  logged_in boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.areas (
  id serial primary key,
  nama text not null unique,
  sales_id uuid references public.profiles(id),
  aktif boolean not null default true
);

create table if not exists public.stores (
  id serial primary key,
  nama text not null,
  area_id int not null references public.areas(id),
  aktif boolean not null default true,
  unique (area_id, nama)
);

do $$ begin
  alter table public.profiles add constraint profiles_store_fk foreign key (store_id) references public.stores(id);
exception when duplicate_object then null;
end $$;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('mt', 'manajer', 'trainer', 'sales', 'pc'));
alter table public.profiles drop constraint if exists profiles_pc_store_check;
alter table public.profiles add constraint profiles_pc_store_check check (role <> 'pc' or store_id is not null);

-- Trainer memegang Sales. Satu Sales punya satu Trainer.
create table if not exists public.trainer_sales (
  sales_id uuid primary key references public.profiles(id) on delete cascade,
  trainer_id uuid not null references public.profiles(id) on delete cascade
);

-- Kode produk dipakai bersama semua area (insentif per produk mengacu ke kode ini).
create sequence if not exists public.produk_kode_seq;

-- Daftar induk produk: salinan awal untuk setiap area baru (dan "tambah ke semua area" oleh MT).
create table if not exists public.produk_master (
  kode text primary key default ('P' || lpad(nextval('public.produk_kode_seq')::text, 4, '0')),
  tipe text not null check (tipe in ('HP', 'IOT')),
  nama text not null,
  grup text not null,
  harga bigint not null check (harga >= 0),
  fokus text,
  urutan int not null default 0,
  insentif_awal bigint,
  aktif boolean not null default true,
  unique (tipe, nama)
);

-- Produk per area. Perubahan di satu area tidak mengubah area lain.
create table if not exists public.products (
  id serial primary key,
  area_id int not null references public.areas(id),
  kode text not null default ('P' || lpad(nextval('public.produk_kode_seq')::text, 4, '0')),
  tipe text not null check (tipe in ('HP', 'IOT')),
  nama text not null,
  grup text not null,
  harga bigint not null check (harga >= 0),
  fokus text,
  urutan int not null default 0,
  aktif boolean not null default true,
  diubah_oleh uuid references public.profiles(id),
  diubah_pada timestamptz not null default now(),
  unique (area_id, kode),
  unique (area_id, tipe, nama)
);

create table if not exists public.competitor_brands (
  id serial primary key,
  nama text not null unique,
  urutan int not null default 0,
  aktif boolean not null default true
);

-- ---------------------------------------------------------------------
-- 2. TABEL TRANSAKSI HARIAN
-- ---------------------------------------------------------------------
-- Penjualan OPPO per PC
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid not null references public.profiles(id),
  diinput_oleh uuid references public.profiles(id),
  tanggal date not null,
  product_id int references public.products(id),
  kode text,
  tipe text not null check (tipe in ('HP', 'IOT')),
  nama_produk text not null,
  grup text,
  fokus text,
  qty int not null check (qty > 0),
  harga bigint not null check (harga >= 0),
  subtotal bigint generated always as (qty * harga) stored,
  metode text check (metode in ('Cash', 'Kredit')),
  cara_bayar text,
  kategori_user text check (kategori_user is null or kategori_user in ('Walk-in', 'Databased', 'Online')),
  created_at timestamptz not null default now(),
  check (
    (metode is null and cara_bayar is null)
    or (metode = 'Cash' and cara_bayar in ('Transfer', 'Tunai'))
    or (metode = 'Kredit' and cara_bayar in ('Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit'))
  )
);
create index if not exists sales_store_idx on public.sales(store_id, tanggal);
create index if not exists sales_pc_idx on public.sales(pc_id, tanggal);

-- Tanda nihil per PC: NOSELL (penjualan) dan "tidak ada pengajuan cek limit hari ini"
create table if not exists public.checkins (
  pc_id uuid not null references public.profiles(id),
  tanggal date not null,
  modul text not null check (modul in ('penjualan', 'cek_limit')),
  store_id int references public.stores(id),
  oleh uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (pc_id, tanggal, modul)
);

-- STOK per toko (semua PC di toko memakai angka yang sama).
-- Hemat database: hanya stok TERKINI (1 baris per toko per produk) + riwayat perubahan.
--   1. PC menghitung stok fisik sekali = stok awal (stores.stok_awal_pada).
--   2. Setiap penjualan sesudahnya otomatis memotong stok (edit/hapus ikut menyesuaikan).
--      Penjualan bertanggal SEBELUM tanggal stok awal tidak memotong stok.
--   3. Setiap hari PC cek & koreksi (barang masuk / selisih), lalu simpan.
alter table public.stores add column if not exists stok_awal_pada timestamptz;
alter table public.stores add column if not exists stok_awal_tanggal date;

create table if not exists public.stok (
  store_id int not null references public.stores(id),
  product_id int not null references public.products(id),
  qty int not null default 0,                    -- boleh minus (terjual sebelum barang masuk diinput)
  updated_at timestamptz not null default now(),
  primary key (store_id, product_id)
);

-- Riwayat perubahan stok: awal, koreksi (barang masuk / selisih), jual, batal_jual
create table if not exists public.stok_mutasi (
  id bigserial primary key,
  store_id int not null references public.stores(id),
  product_id int not null references public.products(id),
  tanggal date not null,
  jenis text not null check (jenis in ('awal', 'masuk', 'koreksi', 'jual', 'batal_jual')),
  perubahan int not null,
  sesudah int not null,
  sale_id uuid,
  oleh uuid references public.profiles(id),
  waktu timestamptz not null default now()
);
create index if not exists stok_mutasi_idx on public.stok_mutasi(store_id, tanggal);
alter table public.stok_mutasi drop constraint if exists stok_mutasi_jenis_check;
alter table public.stok_mutasi add constraint stok_mutasi_jenis_check
  check (jenis in ('awal', 'masuk', 'koreksi', 'jual', 'batal_jual'));

-- Tanda "stok sudah dicek hari ini" per toko + total stok saat itu (untuk laporan & export)
create table if not exists public.stok_update (
  store_id int not null references public.stores(id),
  tanggal date not null,
  pertama timestamptz not null default now(),
  terakhir timestamptz not null default now(),
  oleh uuid references public.profiles(id),
  stok_hp int,
  stok_iot int,
  primary key (store_id, tanggal)
);

-- MS Allbrand per toko: total per brand + rincian per segmen harga
create table if not exists public.competitor_sales (
  store_id int not null references public.stores(id),
  tanggal date not null,
  brand_id int not null references public.competitor_brands(id),
  unit int not null default 0 check (unit >= 0),
  diinput_oleh uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, tanggal, brand_id)
);

create table if not exists public.competitor_sales_detail (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  brand_id int not null references public.competitor_brands(id),
  segmen text not null check (segmen in ('lt3', '3to6', 'gt6')),
  unit int not null check (unit > 0),
  diinput_oleh uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists competitor_sales_detail_idx on public.competitor_sales_detail(store_id, tanggal);

-- Cek limit leasing per PC (tanpa foto)
create table if not exists public.leasing_checks (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid not null references public.profiles(id),
  diinput_oleh uuid references public.profiles(id),
  tanggal date not null,
  leasing text not null check (leasing in ('Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit')),
  hasil text not null check (hasil in ('Approve', 'Reject')),
  limit_disetujui bigint,
  created_at timestamptz not null default now(),
  check (hasil = 'Reject' or coalesce(limit_disetujui, 0) > 0)
);
create index if not exists leasing_checks_pc_idx on public.leasing_checks(pc_id, tanggal);

-- Laporan terkirim per PC (batas 22.30 WIB)
create table if not exists public.daily_reports (
  pc_id uuid not null references public.profiles(id),
  tanggal date not null,
  store_id int not null references public.stores(id),
  dikirim_oleh uuid references public.profiles(id),
  dikirim_pada timestamptz not null default now(),
  primary key (pc_id, tanggal)
);

-- Offday / izin PC. Tanggal tanpa baris = hari kerja.
create table if not exists public.pc_day_status (
  pc_id uuid not null references public.profiles(id) on delete cascade,
  tanggal date not null,
  status text not null check (status in ('offday', 'izin', 'sakit')),
  dibuat_oleh uuid references public.profiles(id),
  dibuat_pada timestamptz not null default now(),
  primary key (pc_id, tanggal)
);
alter table public.pc_day_status drop constraint if exists pc_day_status_status_check;
alter table public.pc_day_status add constraint pc_day_status_status_check check (status in ('offday', 'izin', 'sakit'));

-- Target harian yang diatur atasan untuk satu PC pada satu tanggal (menggantikan hitungan otomatis).
-- Kolom kosong = pakai hitungan otomatis (sisa target ÷ sisa hari kerja).
create table if not exists public.pc_target_harian (
  pc_id uuid not null references public.profiles(id) on delete cascade,
  tanggal date not null,
  unit numeric check (unit >= 0),
  value numeric check (value >= 0),
  fokus numeric check (fokus >= 0),
  iot numeric check (iot >= 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (pc_id, tanggal)
);

-- Target bulanan per toko dan per PC. bulan = tanggal 1. fokus = semua produk bertanda tipe fokus.
create table if not exists public.store_targets (
  store_id int not null references public.stores(id) on delete cascade,
  bulan date not null check (extract(day from bulan) = 1),
  jenis text not null check (jenis in ('unit', 'value', 'fokus', 'iot', 'iot_value')),
  nilai numeric not null default 0 check (nilai >= 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, bulan, jenis)
);

-- Target bulanan per Sales (seluruh area Sales). Jika ada, menggantikan jumlah target toko untuk Sales itu.
-- Target Trainer = jumlah target semua Sales yang dipegang.
create table if not exists public.sales_targets (
  sales_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null check (extract(day from bulan) = 1),
  jenis text not null check (jenis in ('unit', 'value', 'fokus', 'iot', 'iot_value')),
  nilai numeric not null default 0 check (nilai >= 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (sales_id, bulan, jenis)
);

create table if not exists public.pc_targets (
  pc_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null check (extract(day from bulan) = 1),
  jenis text not null check (jenis in ('unit', 'value', 'fokus', 'iot', 'iot_value')),
  nilai numeric not null default 0 check (nilai >= 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (pc_id, bulan, jenis)
);

-- Riwayat perubahan produk, harga, KPI, dan target
create table if not exists public.audit_log (
  id bigserial primary key,
  tabel text not null,
  ref text not null,
  aksi text not null,
  nilai_lama jsonb,
  nilai_baru jsonb,
  oleh uuid references public.profiles(id),
  waktu timestamptz not null default now()
);
create index if not exists audit_log_waktu_idx on public.audit_log(waktu desc);

create table if not exists public.login_log (
  id bigserial primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  jenis text not null check (jenis in ('login', 'logout', 'buka')),
  waktu timestamptz not null default now()
);
create index if not exists login_log_profile_idx on public.login_log(profile_id, waktu desc);

-- ---------------------------------------------------------------------
-- 3. KPI & INSENTIF (per Trainer per bulan; berlaku untuk semua area Sales yang dipegang)
-- Rumus estimasi gaji PC (bulan berjalan, dari penjualan PC itu sendiri):
--   Tier ditentukan dari value HP (dan unit HP untuk tier dengan unit minimal)
--   Gaji pokok   = UMR - potongan sesuai unit HP   (tier dengan "gaji % UMR": UMR x persen)
--   Insentif HP  = jumlah insentif per unit HP x persen insentif tier
--   Insentif IoT = jumlah insentif per unit IoT (100%)
--   Bonus        = aturan bonus yang tercapai (satu grup: ambil yang terbesar)
--   Denda        = aturan denda yang tidak tercapai
-- ---------------------------------------------------------------------
create table if not exists public.kpi_gaji (
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null check (extract(day from bulan) = 1),
  umr bigint not null check (umr >= 0),
  primary key (trainer_id, bulan)
);

create table if not exists public.kpi_tier (
  id bigserial primary key,
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  urutan int not null default 0,
  nama text not null,
  value_min bigint,
  value_max bigint,
  unit_min int,
  persen_insentif numeric not null default 100 check (persen_insentif between 0 and 100),
  gaji_persen_umr numeric check (gaji_persen_umr between 0 and 100)
);
create index if not exists kpi_tier_idx on public.kpi_tier(trainer_id, bulan, urutan);

create table if not exists public.kpi_potongan (
  id bigserial primary key,
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  unit_min int not null default 0,
  unit_max int,
  potongan bigint not null default 0 check (potongan >= 0)
);
create index if not exists kpi_potongan_idx on public.kpi_potongan(trainer_id, bulan);

-- metrik: unit_hp, value_hp, unit_fokus, unit_a7_reno (A7 Pro + Reno Series), unit_iot,
--         unit_produk (nama produk mengandung filter), cek_limit (filter = nama leasing)
create table if not exists public.kpi_aturan (
  id bigserial primary key,
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  jenis text not null check (jenis in ('bonus', 'denda')),
  nama text not null,
  metrik text not null check (metrik in ('unit_hp', 'value_hp', 'unit_fokus', 'unit_a7_reno', 'unit_iot', 'unit_produk', 'cek_limit')),
  filter text,
  batas_min numeric not null default 0,
  batas_max numeric,
  nilai bigint not null check (nilai >= 0),
  per_unit boolean not null default false,
  grup text,
  urutan int not null default 0
);
create index if not exists kpi_aturan_idx on public.kpi_aturan(trainer_id, bulan, jenis, urutan);

-- Insentif per unit produk, mengacu ke kode produk (sama di semua area)
create table if not exists public.insentif_produk (
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  kode text not null,
  nilai bigint not null default 0 check (nilai >= 0),
  primary key (trainer_id, bulan, kode)
);

-- Insentif produk tanpa nilai khusus (OTHERS)
create table if not exists public.insentif_lain (
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  kode text not null check (kode in ('hp_lt2', 'hp_2to3', 'hp_gt3', 'hp_reno', 'hp_find', 'iot_lain')),
  nilai bigint not null default 0 check (nilai >= 0),
  primary key (trainer_id, bulan, kode)
);

-- Bonus per unit untuk setiap tipe fokus (label products.fokus) di wilayah Trainer.
-- Tipe fokus dipilih MT / Trainer dari list produk (RPC atur_fokus); bonus = nilai x unit terjual bulan itu.
create table if not exists public.kpi_fokus (
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  bulan date not null,
  fokus text not null,
  nilai bigint not null default 0 check (nilai >= 0),
  primary key (trainer_id, bulan, fokus)
);

-- ---------------------------------------------------------------------
-- 4. FUNGSI BANTU & CAKUPAN
-- ---------------------------------------------------------------------
create or replace function public.my_profile_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.my_store_id() returns int
language sql stable security definer set search_path = public as $$
  select store_id from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.is_mt() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'mt', false)
$$;

create or replace function public.is_atasan() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('mt', 'manajer', 'trainer', 'sales'), false)
$$;

-- Boleh mengubah data (Manajer LKA hanya melihat)
create or replace function public.is_pengubah() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('mt', 'trainer', 'sales'), false)
$$;

create or replace function public.today_wib() returns date
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function public.time_wib() returns time
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::time $$;

create or replace function public.server_now() returns timestamptz
language sql stable as $$ select now() $$;

create or replace function public.store_area(p_store int) returns int
language sql stable security definer set search_path = public as $$
  select area_id from public.stores where id = p_store
$$;

create or replace function public.pc_store(p_pc uuid) returns int
language sql stable security definer set search_path = public as $$
  select store_id from public.profiles where id = p_pc
$$;

-- Trainer pemilik wilayah sebuah area (dari Sales area itu)
create or replace function public.area_trainer(p_area int) returns uuid
language sql stable security definer set search_path = public as $$
  select ts.trainer_id from public.areas a join public.trainer_sales ts on ts.sales_id = a.sales_id where a.id = p_area
$$;

-- Area yang boleh dilihat akun ini
create or replace function public.area_cakupan() returns setof int
language sql stable security definer set search_path = public as $$
  select a.id from public.areas a
   where case public.my_role()
           when 'mt' then true
           when 'manajer' then true
           when 'trainer' then a.sales_id in (select sales_id from public.trainer_sales where trainer_id = public.my_profile_id())
           when 'sales' then a.sales_id = public.my_profile_id()
           when 'pc' then a.id = public.store_area(public.my_store_id())
           else false
         end
$$;

create or replace function public.in_cakupan(p_area int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_area in (select public.area_cakupan())
  ), false)
$$;

-- Lihat toko: atasan sesuai cakupan, PC tokonya
create or replace function public.can_view_store(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    case when public.my_role() = 'pc' then p_store = public.my_store_id()
              else public.in_cakupan(public.store_area(p_store)) end
  ), false)
$$;

-- Kelola toko (target, offday, PC, koreksi data): MT, Trainer, Sales sesuai cakupan
create or replace function public.can_manage_store(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    public.is_pengubah() and public.in_cakupan(public.store_area(p_store))
  ), false)
$$;

-- Lihat data pribadi PC: PC itu sendiri, atasan sesuai cakupan
create or replace function public.can_view_pc(p_pc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_pc = public.my_profile_id() or (public.is_atasan() and public.can_view_store(public.pc_store(p_pc)))
  ), false)
$$;

-- PC masih dalam jam input hari ini (sebelum 22.30 WIB)
create or replace function public.pc_jam_buka(p_tanggal date) returns boolean
language sql stable as $$
  select p_tanggal = public.today_wib() and public.time_wib() < time '22:30'
$$;

-- Stok toko: PC tokonya (tanpa batas jam); atasan cakupan. Tanggal s.d. hari ini.
create or replace function public.can_write_daily(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_tanggal <= public.today_wib() and (
           (public.my_role() = 'pc' and p_store = public.my_store_id())
        or public.can_manage_store(p_store))
  ), false)
$$;

-- Data harian PC (cek limit, tanda nihil): PC sendiri tanggal berapa pun s.d. hari ini; atasan cakupan
create or replace function public.can_write_pc(p_pc uuid, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_tanggal <= public.today_wib() and (
           (p_pc = public.my_profile_id() and public.my_role() = 'pc')
        or public.can_manage_store(public.pc_store(p_pc)))
  ), false)
$$;

-- Penjualan: PC miliknya sendiri tanggal berapa pun s.d. hari ini; atasan cakupan (koreksi)
create or replace function public.can_write_sales(p_store int, p_pc uuid, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_tanggal <= public.today_wib() and (
           (public.my_role() = 'pc' and p_pc = public.my_profile_id() and p_store = public.my_store_id())
        or public.can_manage_store(p_store))
  ), false)
$$;

-- MS Allbrand: PC tokonya tgl 1 s.d. hari ini di bulan berjalan; atasan cakupan s.d. hari ini
create or replace function public.can_write_ms(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    p_tanggal <= public.today_wib() and (
           (public.my_role() = 'pc' and p_store = public.my_store_id()
              and date_trunc('month', p_tanggal) = date_trunc('month', public.today_wib()::timestamp))
        or public.can_manage_store(p_store))
  ), false)
$$;

create or replace function public.segmen_harga(p_harga bigint) returns text
language sql immutable as $$
  select case when p_harga < 3000000 then 'lt3' when p_harga < 6000000 then '3to6' else 'gt6' end
$$;

-- ---------------------------------------------------------------------
-- 5. TRIGGER
-- ---------------------------------------------------------------------
-- Hubungkan akun login ke profil berdasarkan email
create or replace function public.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set auth_uid = new.id where lower(email) = lower(new.email) and auth_uid is null;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Login dihapus (reset password / nonaktif): tandai tidak login
create or replace function public.on_auth_uid_null() returns trigger
language plpgsql as $$
begin
  if new.auth_uid is null and old.auth_uid is not null then new.logged_in := false; end if;
  return new;
end $$;
drop trigger if exists trg_auth_uid_null on public.profiles;
create trigger trg_auth_uid_null before update of auth_uid on public.profiles
  for each row execute function public.on_auth_uid_null();

-- Penjualan: nama, grup, tipe, kode, fokus, harga dari produk area toko (tidak bisa diakali dari HP)
create or replace function public.fill_sale_from_product() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.products;
begin
  if tg_op = 'INSERT' then
    if new.pc_id is null and public.my_role() = 'pc' then new.pc_id := public.my_profile_id(); end if;
    if new.pc_id is null then raise exception 'PC penjualan wajib diisi'; end if;
    if public.pc_store(new.pc_id) is distinct from new.store_id then raise exception 'PC tidak berada di toko ini'; end if;
    new.diinput_oleh := coalesce(public.my_profile_id(), new.diinput_oleh);
  end if;
  if new.product_id is not null and (tg_op = 'INSERT' or new.product_id is distinct from old.product_id) then
    select * into p from public.products where id = new.product_id;
    if p.id is null then raise exception 'Produk tidak ditemukan'; end if;
    if p.area_id <> public.store_area(new.store_id) then raise exception 'Produk bukan milik area toko ini'; end if;
    new.nama_produk := p.nama;
    new.grup := p.grup;
    new.tipe := p.tipe;
    new.kode := p.kode;
    new.fokus := p.fokus;
    new.harga := p.harga;
  end if;
  return new;
end $$;
drop trigger if exists trg_sale_fill on public.sales;
create trigger trg_sale_fill before insert or update on public.sales
  for each row execute function public.fill_sale_from_product();

-- Ada penjualan: tanda NOSELL tanggal itu tidak berlaku lagi
create or replace function public.clear_nosell() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.checkins where pc_id = new.pc_id and tanggal = new.tanggal and modul = 'penjualan';
  return null;
end $$;
drop trigger if exists trg_clear_nosell on public.sales;
create trigger trg_clear_nosell after insert on public.sales for each row execute function public.clear_nosell();

-- Ada cek limit: tanda "tidak ada pengajuan" tidak berlaku lagi
create or replace function public.clear_nolimit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.checkins where pc_id = new.pc_id and tanggal = new.tanggal and modul = 'cek_limit';
  return null;
end $$;
drop trigger if exists trg_clear_nolimit on public.leasing_checks;
create trigger trg_clear_nolimit after insert on public.leasing_checks for each row execute function public.clear_nolimit();

-- Pelaku diisi dari akun yang login
create or replace function public.set_pelaku() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.diinput_oleh := coalesce(public.my_profile_id(), new.diinput_oleh);
  if new.pc_id is null and public.my_role() = 'pc' then new.pc_id := public.my_profile_id(); end if;
  if new.store_id is null then new.store_id := public.pc_store(new.pc_id); end if;
  return new;
end $$;
drop trigger if exists trg_pelaku_leasing on public.leasing_checks;
create trigger trg_pelaku_leasing before insert on public.leasing_checks for each row execute function public.set_pelaku();

-- Stok: penjualan memotong stok toko (hanya setelah stok awal toko disimpan)
alter table public.sales add column if not exists potong_stok boolean not null default false;

create or replace function public.ubah_stok(p_store int, p_product int, p_ubah int, p_tanggal date, p_jenis text,
                                            p_sale uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_sesudah int;
begin
  if p_product is null or p_ubah = 0 then return; end if;
  insert into public.stok (store_id, product_id, qty, updated_at) values (p_store, p_product, p_ubah, now())
  on conflict (store_id, product_id) do update set qty = public.stok.qty + p_ubah, updated_at = now()
  returning qty into v_sesudah;
  insert into public.stok_mutasi (store_id, product_id, tanggal, jenis, perubahan, sesudah, sale_id, oleh)
  values (p_store, p_product, p_tanggal, p_jenis, p_ubah, v_sesudah, p_sale, public.my_profile_id());
end $$;
revoke execute on function public.ubah_stok(int, int, int, date, text, uuid) from public, anon, authenticated;

-- Sebelum simpan: tentukan apakah penjualan ini memotong stok
create or replace function public.tandai_potong_stok() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_awal date;
begin
  if tg_op = 'UPDATE' and new.tanggal = old.tanggal and new.store_id = old.store_id then
    new.potong_stok := old.potong_stok;
    return new;
  end if;
  select stok_awal_tanggal into v_awal from public.stores where id = new.store_id;
  new.potong_stok := v_awal is not null and new.tanggal >= v_awal and new.product_id is not null;
  return new;
end $$;
drop trigger if exists trg_tandai_potong_stok on public.sales;
create trigger trg_tandai_potong_stok before insert or update on public.sales
  for each row execute function public.tandai_potong_stok();

-- Sesudah simpan: kembalikan potongan lama, terapkan potongan baru
create or replace function public.stok_dari_penjualan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Pembersihan data lama / hapus permanen PC: stok toko tidak ikut berubah
  if coalesce(current_setting('lka.bersih', true), '') = '1' then return null; end if;
  if tg_op in ('UPDATE', 'DELETE') and old.potong_stok then
    perform public.ubah_stok(old.store_id, old.product_id, old.qty, public.today_wib(), 'batal_jual', old.id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.potong_stok then
    perform public.ubah_stok(new.store_id, new.product_id, -new.qty, public.today_wib(), 'jual', new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_stok_dari_penjualan on public.sales;
create trigger trg_stok_dari_penjualan after insert or update or delete on public.sales
  for each row execute function public.stok_dari_penjualan();

-- Apple hanya segmen 6 jt up
create or replace function public.cek_segmen_brand() returns trigger
language plpgsql as $$
begin
  if new.segmen <> 'gt6' and exists (select 1 from public.competitor_brands where id = new.brand_id and lower(nama) = 'apple') then
    raise exception 'Apple hanya untuk segmen 6 jt up';
  end if;
  return new;
end $$;
drop trigger if exists trg_cek_segmen_brand on public.competitor_sales_detail;
create trigger trg_cek_segmen_brand before insert or update on public.competitor_sales_detail
  for each row execute function public.cek_segmen_brand();

-- Penanda pengubah produk & target
create or replace function public.set_pengubah() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'products' then
    new.diubah_oleh := public.my_profile_id();
    new.diubah_pada := now();
  else
    new.updated_by := public.my_profile_id();
    new.updated_at := now();
  end if;
  return new;
end $$;
do $$
declare t text;
begin
  foreach t in array array['products', 'store_targets', 'pc_targets', 'pc_target_harian', 'sales_targets'] loop
    execute format('drop trigger if exists trg_pengubah on public.%I', t);
    execute format('create trigger trg_pengubah before insert or update on public.%I for each row execute function public.set_pengubah()', t);
  end loop;
end $$;

-- Riwayat perubahan (siapa, kapan, dari berapa ke berapa)
create or replace function public.audit_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_ref text;
begin
  if coalesce(current_setting('lka.bersih', true), '') = '1' then return null; end if;
  v_ref := case tg_table_name
    when 'products' then coalesce(j->>'area_id', '') || '|' || coalesce(j->>'kode', '')
    when 'store_targets' then (j->>'store_id') || '|' || (j->>'bulan') || '|' || (j->>'jenis')
    when 'pc_targets' then (j->>'pc_id') || '|' || (j->>'bulan') || '|' || (j->>'jenis')
    when 'sales_targets' then (j->>'sales_id') || '|' || (j->>'bulan') || '|' || (j->>'jenis')
    when 'pc_target_harian' then (j->>'pc_id') || '|' || (j->>'tanggal')
    when 'insentif_produk' then (j->>'trainer_id') || '|' || (j->>'bulan') || '|' || (j->>'kode')
    when 'insentif_lain' then (j->>'trainer_id') || '|' || (j->>'bulan') || '|' || (j->>'kode')
    when 'kpi_fokus' then (j->>'trainer_id') || '|' || (j->>'bulan') || '|' || (j->>'fokus')
    when 'kpi_gaji' then (j->>'trainer_id') || '|' || (j->>'bulan')
    else coalesce(j->>'id', '-') end;
  if tg_op = 'UPDATE' and to_jsonb(old) - 'diubah_pada' - 'updated_at' = to_jsonb(new) - 'diubah_pada' - 'updated_at' then
    return null;
  end if;
  insert into public.audit_log (tabel, ref, aksi, nilai_lama, nilai_baru, oleh)
  values (tg_table_name, v_ref, tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          public.my_profile_id());
  return null;
end $$;
do $$
declare t text;
begin
  foreach t in array array['products', 'store_targets', 'pc_targets', 'pc_target_harian', 'sales_targets', 'kpi_gaji', 'kpi_tier', 'kpi_potongan',
                           'kpi_aturan', 'insentif_produk', 'insentif_lain', 'kpi_fokus'] loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I for each row execute function public.audit_change()', t);
  end loop;
end $$;

-- Area baru: salin list produk induk (list produk HP & IoT NKA) ke area itu
create or replace function public.salin_produk_ke_area(p_area int) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.products (area_id, kode, tipe, nama, grup, harga, fokus, urutan)
  select p_area, m.kode, m.tipe, m.nama, m.grup, m.harga, m.fokus, m.urutan
    from public.produk_master m
   where m.aktif
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.salin_produk_ke_area(int) from public, anon, authenticated;

create or replace function public.on_area_baru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.salin_produk_ke_area(new.id);
  return null;
end $$;
drop trigger if exists trg_area_baru on public.areas;
create trigger trg_area_baru after insert on public.areas for each row execute function public.on_area_baru();

-- ---------------------------------------------------------------------
-- 6. KPI: FUNGSI
-- ---------------------------------------------------------------------
-- Aturan KPI awal (sama dengan NKA November 2026) untuk satu Trainer pada satu bulan
create or replace function public.kpi_awal(p_trainer uuid, p_bulan date) returns void
language plpgsql security definer set search_path = public as $$
declare b date := date_trunc('month', p_bulan)::date;
begin
  if exists (select 1 from public.kpi_gaji where trainer_id = p_trainer) then return; end if;
  insert into public.kpi_gaji values (p_trainer, b, 3724700);
  insert into public.kpi_tier (trainer_id, bulan, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr) values
    (p_trainer, b, 1, 'Tier 1', 160000000, null, null, 100, null),
    (p_trainer, b, 2, 'Tier 2', 130000000, 160000000, null, 90, null),
    (p_trainer, b, 3, 'Tier 3', 90000000, 130000000, null, 70, null),
    (p_trainer, b, 4, 'Tier 4', 70000000, 90000000, null, 60, null),
    (p_trainer, b, 5, 'Tier 5', null, 70000000, 15, 100, null),
    (p_trainer, b, 6, 'Tier 6', null, 70000000, 10, 50, null),
    (p_trainer, b, 7, 'Tier 7', null, 70000000, null, 0, 50);
  insert into public.kpi_potongan (trainer_id, bulan, unit_min, unit_max, potongan) values
    (p_trainer, b, 70, null, 0),
    (p_trainer, b, 60, 69, 1200000),
    (p_trainer, b, 50, 59, 1300000),
    (p_trainer, b, 40, 49, 1400000),
    (p_trainer, b, 0, 39, 1500000);
  insert into public.kpi_aturan (trainer_id, bulan, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan) values
    (p_trainer, b, 'bonus', 'Bonus HP 30 unit', 'unit_hp', null, 30, null, 300000, false, 'bonus_hp', 1),
    (p_trainer, b, 'bonus', 'Bonus HP 40 unit', 'unit_hp', null, 40, null, 400000, false, 'bonus_hp', 2),
    (p_trainer, b, 'bonus', 'Bonus HP 50 unit', 'unit_hp', null, 50, null, 500000, false, 'bonus_hp', 3),
    (p_trainer, b, 'bonus', 'Bonus HP 60 unit', 'unit_hp', null, 60, null, 600000, false, 'bonus_hp', 4),
    (p_trainer, b, 'bonus', 'Bonus HP 70 unit ke atas', 'unit_hp', null, 70, null, 800000, false, 'bonus_hp', 5),
    (p_trainer, b, 'bonus', 'Tipe fokus 5-10 unit (30K/unit)', 'unit_fokus', null, 5, 10, 30000, true, 'bonus_fokus', 6),
    (p_trainer, b, 'bonus', 'Tipe fokus 11 unit ke atas (50K/unit)', 'unit_fokus', null, 11, null, 50000, true, 'bonus_fokus', 7),
    (p_trainer, b, 'bonus', 'IoT 10 unit ke atas', 'unit_iot', null, 10, null, 200000, false, 'bonus_iot', 8),
    (p_trainer, b, 'bonus', 'Enco Air 5 Series minimal 3 unit', 'unit_produk', 'Air5', 3, null, 200000, false, 'bonus_enco', 9),
    (p_trainer, b, 'denda', 'A7 Pro + Reno Series 0 unit', 'unit_a7_reno', null, 1, null, 200000, false, null, 1),
    (p_trainer, b, 'denda', 'IoT 0 unit', 'unit_iot', null, 1, null, 100000, false, null, 2),
    (p_trainer, b, 'denda', 'Cek limit Avanto kurang dari 20 kali (10K/kekurangan)', 'cek_limit', 'Avanto', 20, null, 10000, true, null, 3);
  insert into public.insentif_lain (trainer_id, bulan, kode, nilai) values
    (p_trainer, b, 'hp_lt2', 15000), (p_trainer, b, 'hp_2to3', 30000), (p_trainer, b, 'hp_gt3', 50000),
    (p_trainer, b, 'hp_reno', 100000), (p_trainer, b, 'hp_find', 120000), (p_trainer, b, 'iot_lain', 0);
  insert into public.insentif_produk (trainer_id, bulan, kode, nilai)
  select p_trainer, b, kode, insentif_awal from public.produk_master where insentif_awal is not null
  on conflict do nothing;
end $$;
revoke execute on function public.kpi_awal(uuid, date) from public, anon, authenticated;

-- Trainer baru langsung mendapat aturan KPI awal
create or replace function public.on_trainer_baru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'trainer' then perform public.kpi_awal(new.id, public.today_wib()); end if;
  return null;
end $$;
drop trigger if exists trg_trainer_baru on public.profiles;
create trigger trg_trainer_baru after insert or update of role on public.profiles
  for each row execute function public.on_trainer_baru();

-- Bulan aturan yang berlaku: bulan itu, atau bulan terakhir sebelumnya yang punya aturan
create or replace function public.bulan_kpi(p_trainer uuid, p_bulan date) returns date
language sql stable security definer set search_path = public as $$
  select max(bulan) from public.kpi_gaji where trainer_id = p_trainer and bulan <= date_trunc('month', p_bulan)::date
$$;

create or replace function public.insentif_unit(p_trainer uuid, p_bulan date, p_kode text, p_tipe text,
                                                p_grup text, p_harga bigint) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nilai from public.insentif_produk where trainer_id = p_trainer and bulan = p_bulan and kode = p_kode),
    (select nilai from public.insentif_lain where trainer_id = p_trainer and bulan = p_bulan and kode =
       case when p_tipe <> 'HP' then 'iot_lain'
            when p_grup = 'Reno Series' then 'hp_reno'
            when p_grup = 'Find Series' then 'hp_find'
            when p_harga < 2000000 then 'hp_lt2'
            when p_harga <= 3000000 then 'hp_2to3'
            else 'hp_gt3' end),
    0)
$$;

-- Salin semua aturan Trainer (akun sendiri) dari bulan p_dari ke bulan p_ke
drop function if exists public.salin_kpi(date, date);
create or replace function public.salin_kpi(p_dari date, p_ke date, p_trainer uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  t uuid := case when public.is_mt() then coalesce(p_trainer, public.my_profile_id()) else public.my_profile_id() end;
  d date := date_trunc('month', p_dari)::date;
  k date := date_trunc('month', p_ke)::date;
begin
  if not coalesce(public.is_mt() or public.my_role() = 'trainer', false) then raise exception 'KPI hanya bisa diubah oleh Trainer atau MT'; end if;
  if not exists (select 1 from public.profiles where id = t and role = 'trainer') then raise exception 'Pilih Trainer'; end if;
  if d = k then return; end if;
  if not exists (select 1 from public.kpi_gaji where trainer_id = t and bulan = d) then
    raise exception 'Bulan sumber belum punya aturan';
  end if;
  delete from public.kpi_gaji where trainer_id = t and bulan = k;
  delete from public.kpi_tier where trainer_id = t and bulan = k;
  delete from public.kpi_potongan where trainer_id = t and bulan = k;
  delete from public.kpi_aturan where trainer_id = t and bulan = k;
  delete from public.insentif_produk where trainer_id = t and bulan = k;
  delete from public.insentif_lain where trainer_id = t and bulan = k;
  delete from public.kpi_fokus where trainer_id = t and bulan = k;
  insert into public.kpi_gaji select trainer_id, k, umr from public.kpi_gaji where trainer_id = t and bulan = d;
  insert into public.kpi_tier (trainer_id, bulan, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr)
    select trainer_id, k, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr
      from public.kpi_tier where trainer_id = t and bulan = d;
  insert into public.kpi_potongan (trainer_id, bulan, unit_min, unit_max, potongan)
    select trainer_id, k, unit_min, unit_max, potongan from public.kpi_potongan where trainer_id = t and bulan = d;
  insert into public.kpi_aturan (trainer_id, bulan, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan)
    select trainer_id, k, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan
      from public.kpi_aturan where trainer_id = t and bulan = d;
  insert into public.insentif_produk select trainer_id, k, kode, nilai from public.insentif_produk where trainer_id = t and bulan = d;
  insert into public.insentif_lain select trainer_id, k, kode, nilai from public.insentif_lain where trainer_id = t and bulan = d;
  insert into public.kpi_fokus select trainer_id, k, fokus, nilai from public.kpi_fokus where trainer_id = t and bulan = d;
end $$;

-- Estimasi gaji satu PC pada bulan p_tanggal, dihitung s.d. p_tanggal
create or replace function public.estimasi_gaji(p_pc uuid, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_store int := public.pc_store(p_pc);
  v_trainer uuid;
  v_awal date := date_trunc('month', p_tanggal)::date;
  v_b date;
  v_umr bigint;
  v_unit numeric; v_value numeric; v_fokus numeric; v_a7reno numeric; v_iot numeric;
  v_ins_hp numeric; v_ins_iot numeric;
  t record;
  v_tier_nama text;
  v_persen numeric := 0;
  v_gpu numeric;
  v_pot bigint;
  v_gaji numeric;
  a record;
  v_m numeric;
  v_amt numeric;
  v_bonus jsonb := '[]'::jsonb;
  v_denda jsonb := '[]'::jsonb;
  v_grup jsonb := '{}'::jsonb;
  v_tot_bonus numeric := 0;
  v_tot_denda numeric := 0;
  v_tiers jsonb;
begin
  if not public.can_view_pc(p_pc) then raise exception 'Akses ditolak'; end if;
  v_trainer := public.area_trainer(public.store_area(v_store));
  if v_trainer is null then return jsonb_build_object('ada_aturan', false, 'alasan', 'Area ini belum punya Trainer'); end if;
  v_b := public.bulan_kpi(v_trainer, p_tanggal);
  if v_b is null then return jsonb_build_object('ada_aturan', false); end if;
  select umr into v_umr from public.kpi_gaji where trainer_id = v_trainer and bulan = v_b;

  select coalesce(sum(s.qty) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.subtotal) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.qty) filter (where s.fokus is not null), 0),
         coalesce(sum(s.qty) filter (where s.fokus = 'A7 Pro' or s.grup = 'Reno Series'), 0),
         coalesce(sum(s.qty) filter (where s.tipe = 'IOT'), 0),
         coalesce(sum(s.qty * public.insentif_unit(v_trainer, v_b, s.kode, s.tipe, s.grup, s.harga)) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.qty * public.insentif_unit(v_trainer, v_b, s.kode, s.tipe, s.grup, s.harga)) filter (where s.tipe = 'IOT'), 0)
    into v_unit, v_value, v_fokus, v_a7reno, v_iot, v_ins_hp, v_ins_iot
    from public.sales s
   where s.pc_id = p_pc and s.tanggal between v_awal and p_tanggal;

  for t in select * from public.kpi_tier where trainer_id = v_trainer and bulan = v_b order by urutan, id loop
    if (t.value_min is null or v_value >= t.value_min)
       and (t.value_max is null or v_value < t.value_max)
       and (t.unit_min is null or v_unit >= t.unit_min) then
      v_tier_nama := t.nama;
      v_persen := t.persen_insentif;
      v_gpu := t.gaji_persen_umr;
      exit;
    end if;
  end loop;

  select potongan into v_pot from public.kpi_potongan
   where trainer_id = v_trainer and bulan = v_b and v_unit >= unit_min and (unit_max is null or v_unit <= unit_max)
   order by unit_min desc limit 1;
  if v_gpu is not null then
    v_gaji := v_umr * v_gpu / 100;
    v_pot := null;
  else
    v_gaji := v_umr - coalesce(v_pot, 0);
  end if;

  for a in select * from public.kpi_aturan where trainer_id = v_trainer and bulan = v_b order by jenis, urutan, id loop
    v_m := case a.metrik
      when 'unit_hp' then v_unit
      when 'value_hp' then v_value
      when 'unit_fokus' then v_fokus
      when 'unit_a7_reno' then v_a7reno
      when 'unit_iot' then v_iot
      when 'unit_produk' then coalesce((select sum(x.qty) from public.sales x
                                          where x.pc_id = p_pc and x.tanggal between v_awal and p_tanggal
                                            and x.nama_produk ilike '%' || coalesce(a.filter, '') || '%'), 0)
      when 'cek_limit' then coalesce((select count(*) from public.leasing_checks x
                                        where x.pc_id = p_pc and x.tanggal between v_awal and p_tanggal
                                          and (a.filter is null or x.leasing = a.filter)), 0)
      else 0 end;
    if a.jenis = 'bonus' then
      if v_m >= a.batas_min and (a.batas_max is null or v_m <= a.batas_max) then
        v_amt := case when a.per_unit then a.nilai * v_m else a.nilai end;
        if a.grup is not null and coalesce((v_grup ->> a.grup)::numeric, -1) >= v_amt then
          continue;
        end if;
        if a.grup is not null then
          v_bonus := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_bonus) e where e ->> 'grup' is distinct from a.grup), '[]'::jsonb);
          v_grup := v_grup || jsonb_build_object(a.grup, v_amt);
        end if;
        v_bonus := v_bonus || jsonb_build_array(jsonb_build_object('nama', a.nama, 'grup', a.grup, 'capai', v_m, 'jumlah', v_amt));
      end if;
    else
      if v_m < a.batas_min then
        v_amt := case when a.per_unit then a.nilai * (a.batas_min - v_m) else a.nilai end;
        v_denda := v_denda || jsonb_build_array(jsonb_build_object('nama', a.nama, 'capai', v_m, 'target', a.batas_min, 'jumlah', v_amt));
      end if;
    end if;
  end loop;
  -- Bonus tipe fokus: nilai per unit x unit terjual tipe itu bulan ini
  for a in
    select k.fokus, k.nilai, coalesce(sum(s.qty), 0) as unit
      from public.kpi_fokus k
      join public.sales s on s.fokus = k.fokus and s.pc_id = p_pc and s.tanggal between v_awal and p_tanggal
     where k.trainer_id = v_trainer and k.bulan = v_b and k.nilai > 0
     group by k.fokus, k.nilai
  loop
    if a.unit > 0 then
      v_bonus := v_bonus || jsonb_build_array(jsonb_build_object(
        'nama', 'Tipe fokus ' || a.fokus || ' (' || a.nilai || '/unit)', 'grup', null, 'capai', a.unit, 'jumlah', a.nilai * a.unit));
    end if;
  end loop;
  select coalesce(sum((e ->> 'jumlah')::numeric), 0) into v_tot_bonus from jsonb_array_elements(v_bonus) e;
  select coalesce(sum((e ->> 'jumlah')::numeric), 0) into v_tot_denda from jsonb_array_elements(v_denda) e;

  select coalesce(jsonb_agg(jsonb_build_object('nama', nama, 'value_min', value_min, 'value_max', value_max,
                                               'unit_min', unit_min, 'persen', persen_insentif, 'gaji_persen_umr', gaji_persen_umr)
                            order by urutan, id), '[]'::jsonb)
    into v_tiers from public.kpi_tier where trainer_id = v_trainer and bulan = v_b;

  return jsonb_build_object(
    'ada_aturan', true,
    'bulan_aturan', v_b,
    'trainer', (select nama from public.profiles where id = v_trainer),
    'umr', v_umr,
    'unit_hp', v_unit, 'value_hp', v_value, 'unit_fokus', v_fokus, 'unit_a7_reno', v_a7reno, 'unit_iot', v_iot,
    'tier', v_tier_nama,
    'persen_insentif', v_persen,
    'gaji_persen_umr', v_gpu,
    'potongan', v_pot,
    'gaji_pokok', round(v_gaji),
    'insentif_hp_penuh', v_ins_hp,
    'insentif_hp', round(v_ins_hp * v_persen / 100),
    'insentif_iot', v_ins_iot,
    'bonus', v_bonus,
    'denda', v_denda,
    'total_bonus', v_tot_bonus,
    'total_denda', v_tot_denda,
    'total', round(v_gaji + v_ins_hp * v_persen / 100 + v_ins_iot + v_tot_bonus - v_tot_denda),
    'tiers', v_tiers
  );
end $$;

-- Insentif hari ini satu PC
create or replace function public.insentif_harian(p_pc uuid, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_trainer uuid;
  v_b date;
  v_persen numeric := 100;
  v_tier text;
  v_est jsonb;
  r jsonb;
begin
  if not public.can_view_pc(p_pc) then raise exception 'Akses ditolak'; end if;
  v_trainer := public.area_trainer(public.store_area(public.pc_store(p_pc)));
  v_b := public.bulan_kpi(v_trainer, p_tanggal);
  if v_b is null then return jsonb_build_object('ada_aturan', false); end if;
  begin
    v_est := public.estimasi_gaji(p_pc, p_tanggal);
    v_persen := coalesce((v_est->>'persen_insentif')::numeric, 100);
    v_tier := v_est->>'tier';
  exception when others then null;
  end;
  with x as (
    select s.tipe, s.nama_produk, s.qty, s.created_at,
           public.insentif_unit(v_trainer, v_b, s.kode, s.tipe, s.grup, s.harga) as per_unit
      from public.sales s
     where s.pc_id = p_pc and s.tanggal = p_tanggal
  )
  select jsonb_build_object(
    'ada_aturan', true,
    'tier', v_tier,
    'persen_hp', v_persen,
    'total_hp', coalesce((select sum(qty * per_unit) from x where tipe = 'HP'), 0),
    'total_hp_tier', coalesce((select sum(qty * per_unit) from x where tipe = 'HP'), 0) * v_persen / 100,
    'total_iot', coalesce((select sum(qty * per_unit) from x where tipe = 'IOT'), 0),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                'tipe', tipe, 'nama', nama_produk, 'qty', qty, 'per_unit', per_unit, 'insentif', qty * per_unit)
                order by tipe, created_at) from x), '[]'::jsonb)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles', 'areas', 'stores', 'trainer_sales', 'produk_master', 'products', 'competitor_brands',
                           'sales', 'checkins', 'competitor_sales', 'competitor_sales_detail',
                           'leasing_checks', 'daily_reports', 'pc_day_status', 'store_targets', 'pc_targets', 'pc_target_harian', 'sales_targets',
                           'audit_log', 'login_log', 'kpi_gaji', 'kpi_tier', 'kpi_potongan', 'kpi_aturan',
                           'insentif_produk', 'insentif_lain', 'kpi_fokus'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Master: semua akun login bisa baca; MT bisa ubah langsung (lainnya lewat RPC)
do $$
declare t text;
begin
  foreach t in array array['profiles', 'areas', 'stores', 'trainer_sales', 'produk_master', 'products', 'competitor_brands'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_mt', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_mt()) with check (public.is_mt())', t || '_mt', t);
  end loop;
end $$;

-- Produk area: MT (semua), Trainer (area cakupan), Sales (areanya sendiri) boleh tambah & ubah. Tidak ada hapus.
drop policy if exists products_ins on public.products;
create policy products_ins on public.products for insert to authenticated
  with check (public.is_pengubah() and public.in_cakupan(area_id));
drop policy if exists products_upd on public.products;
create policy products_upd on public.products for update to authenticated
  using (public.is_pengubah() and public.in_cakupan(area_id)) with check (public.is_pengubah() and public.in_cakupan(area_id));

-- Penjualan
drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales for insert to authenticated
  with check (public.can_write_sales(store_id, coalesce(pc_id, public.my_profile_id()), tanggal));
drop policy if exists sales_update on public.sales;
create policy sales_update on public.sales for update to authenticated
  using (public.can_write_sales(store_id, pc_id, tanggal)) with check (public.can_write_sales(store_id, pc_id, tanggal));
drop policy if exists sales_delete on public.sales;
create policy sales_delete on public.sales for delete to authenticated using (public.can_write_sales(store_id, pc_id, tanggal));

-- Data harian PC: tanda nihil & cek limit
drop policy if exists checkins_select on public.checkins;
create policy checkins_select on public.checkins for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists checkins_write on public.checkins;
create policy checkins_write on public.checkins for all to authenticated
  using (public.can_write_pc(pc_id, tanggal)) with check (public.can_write_pc(pc_id, tanggal));
drop policy if exists leasing_checks_select on public.leasing_checks;
create policy leasing_checks_select on public.leasing_checks for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists leasing_checks_write on public.leasing_checks;
create policy leasing_checks_write on public.leasing_checks for all to authenticated
  using (public.can_write_pc(coalesce(pc_id, public.my_profile_id()), tanggal))
  with check (public.can_write_pc(coalesce(pc_id, public.my_profile_id()), tanggal));

-- Laporan terkirim: dibaca sesuai cakupan, ditulis lewat RPC kirim_laporan
drop policy if exists daily_reports_select on public.daily_reports;
create policy daily_reports_select on public.daily_reports for select to authenticated using (public.can_view_pc(pc_id));

-- Data harian toko: stok & MS Allbrand
do $$
declare t text;
begin
  foreach t in array array['stok', 'stok_mutasi', 'stok_update', 'competitor_sales', 'competitor_sales_detail'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_view_store(store_id))', t || '_select', t);
  end loop;
end $$;
-- Stok hanya ditulis lewat RPC simpan_stok dan trigger penjualan (tanpa policy tulis)

-- Offday / izin
drop policy if exists pc_day_status_select on public.pc_day_status;
create policy pc_day_status_select on public.pc_day_status for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists pc_day_status_manage on public.pc_day_status;
create policy pc_day_status_manage on public.pc_day_status for all to authenticated
  using (public.can_manage_store(public.pc_store(pc_id))) with check (public.can_manage_store(public.pc_store(pc_id)));

-- Target
drop policy if exists store_targets_select on public.store_targets;
create policy store_targets_select on public.store_targets for select to authenticated using (public.can_view_store(store_id));
drop policy if exists store_targets_manage on public.store_targets;
create policy store_targets_manage on public.store_targets for all to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));
drop policy if exists pc_targets_select on public.pc_targets;
create policy pc_targets_select on public.pc_targets for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists pc_targets_manage on public.pc_targets;
create policy pc_targets_manage on public.pc_targets for all to authenticated
  using (public.can_manage_store(public.pc_store(pc_id))) with check (public.can_manage_store(public.pc_store(pc_id)));
drop policy if exists sales_targets_select on public.sales_targets;
create policy sales_targets_select on public.sales_targets for select to authenticated using (public.is_atasan());
drop policy if exists sales_targets_manage on public.sales_targets;
create policy sales_targets_manage on public.sales_targets for all to authenticated
  using (public.is_mt() or exists (select 1 from public.trainer_sales x where x.sales_id = sales_targets.sales_id and x.trainer_id = public.my_profile_id()))
  with check (public.is_mt() or exists (select 1 from public.trainer_sales x where x.sales_id = sales_targets.sales_id and x.trainer_id = public.my_profile_id()));
drop policy if exists pc_target_harian_select on public.pc_target_harian;
create policy pc_target_harian_select on public.pc_target_harian for select to authenticated using (public.can_view_pc(pc_id));
drop policy if exists pc_target_harian_manage on public.pc_target_harian;
create policy pc_target_harian_manage on public.pc_target_harian for all to authenticated
  using (public.can_manage_store(public.pc_store(pc_id))) with check (public.can_manage_store(public.pc_store(pc_id)));

-- Riwayat perubahan: MT, Trainer, Sales
drop policy if exists audit_log_read on public.audit_log;
create policy audit_log_read on public.audit_log for select to authenticated using (public.is_atasan());

drop policy if exists login_log_select on public.login_log;
create policy login_log_select on public.login_log for select to authenticated using (public.can_view_pc(profile_id) or public.is_mt());

-- KPI: semua akun boleh melihat; ubah oleh Trainer untuk wilayahnya sendiri dan MT untuk semua wilayah
do $$
declare t text;
begin
  foreach t in array array['kpi_gaji', 'kpi_tier', 'kpi_potongan', 'kpi_aturan', 'insentif_produk', 'insentif_lain', 'kpi_fokus'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_trainer', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_mt() or (public.my_role() = ''trainer'' and trainer_id = public.my_profile_id())) with check (public.is_mt() or (public.my_role() = ''trainer'' and trainer_id = public.my_profile_id()))', t || '_trainer', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 8. PENYIMPANAN FILE: hanya APK untuk update di aplikasi (tanpa foto)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('apk', 'apk', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

create or replace function public.info_storage() returns jsonb
language plpgsql stable security definer set search_path = public, storage as $$
begin
  if not public.is_mt() then raise exception 'Akses ditolak'; end if;
  return jsonb_build_object(
    'total', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects),
    'apk_jumlah', (select count(*) from storage.objects where bucket_id = 'apk' and name like '%.apk'),
    'apk_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'apk'),
    'db_bytes', pg_database_size(current_database()),
    'apk', (select coalesce(jsonb_agg(jsonb_build_object('nama', name, 'size', (metadata->>'size')::bigint, 'dibuat', created_at)
                                      order by created_at desc), '[]'::jsonb)
              from storage.objects where bucket_id = 'apk' and name like '%.apk'));
end $$;

-- ---------------------------------------------------------------------
-- 9. RPC AKUN & LOGIN
-- ---------------------------------------------------------------------
create or replace function public.list_login_profiles() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email,
           'toko', coalesce(s.nama, ''),
           'area', coalesce(sa.nama, (select string_agg(a.nama, ', ' order by a.nama) from public.areas a where a.sales_id = p.id), ''),
           'sudah_daftar', p.auth_uid is not null)
         order by case p.role when 'mt' then 0 when 'manajer' then 0 when 'trainer' then 1 when 'sales' then 2 else 3 end, p.nama), '[]'::jsonb)
    from public.profiles p
    left join public.stores s on s.id = p.store_id
    left join public.areas sa on sa.id = s.area_id
   where p.aktif
$$;
grant execute on function public.list_login_profiles() to anon, authenticated;

create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email,
           'store_id', p.store_id, 'toko', coalesce(s.nama, ''),
           'area_id', coalesce(s.area_id, (select min(id) from public.areas where sales_id = p.id)),
           'area', coalesce(a.nama, (select string_agg(nama, ', ' order by nama) from public.areas where sales_id = p.id), ''),
           'sales', (select x.nama from public.profiles x where x.id = a.sales_id),
           'trainer', (select x.nama from public.profiles x where x.id = public.area_trainer(a.id)),
           'jumlah_sales', case when p.role = 'trainer'
                                then (select count(*) from public.trainer_sales where trainer_id = p.id) end)
    from public.profiles p
    left join public.stores s on s.id = p.store_id
    left join public.areas a on a.id = s.area_id
   where p.auth_uid = auth.uid() and p.aktif
$$;

create or replace function public.ping_online() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_seen = now(), logged_in = true where auth_uid = auth.uid()
$$;

create or replace function public.catat_login(p_jenis text default 'login') returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.my_profile_id();
begin
  if v is null then return; end if;
  update public.profiles
     set last_seen = now(), logged_in = true,
         last_login = case when p_jenis = 'login' then now() else last_login end
   where id = v;
  if p_jenis = 'login' or not exists (
       select 1 from public.login_log where profile_id = v and waktu > now() - interval '30 minutes') then
    insert into public.login_log (profile_id, jenis) values (v, case when p_jenis = 'login' then 'login' else 'buka' end);
  end if;
end $$;

create or replace function public.catat_logout() returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.my_profile_id();
begin
  if v is null then return; end if;
  update public.profiles set logged_in = false, last_seen = now() where id = v;
  insert into public.login_log (profile_id, jenis) values (v, 'logout');
end $$;

-- Reset password: MT semua akun selain MT; Trainer & Sales untuk PC di cakupannya.
create or replace function public.reset_password(p_profile uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v public.profiles;
begin
  select * into v from public.profiles where id = p_profile;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.role = 'mt' then raise exception 'Password MT diatur di Supabase'; end if;
  if v.id = public.my_profile_id() then raise exception 'Gunakan menu Ganti password untuk akun sendiri'; end if;
  if not public.boleh_atur_akun(v) then raise exception 'Akses ditolak'; end if;
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set auth_uid = null where id = p_profile;
end $$;

-- Siapa boleh mengatur password akun lain:
--   MT: semua akun selain MT. Trainer: Sales yang dipegang + PC di wilayahnya. Sales: PC di areanya.
create or replace function public.boleh_atur_akun(v public.profiles) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    v.role <> 'mt' and (
       public.is_mt()
    or (v.role = 'pc' and public.can_manage_store(v.store_id))
    or (v.role = 'sales' and public.my_role() = 'trainer'
        and exists (select 1 from public.trainer_sales where sales_id = v.id and trainer_id = public.my_profile_id())))
  ), false)
$$;

-- Atur password baru untuk akun lain (yang sudah pernah login). Password lama tidak bisa dilihat siapa pun
-- (disimpan teracak); yang mengatur tahu password baru ini dan memberitahukannya ke pemilik akun.
create or replace function public.atur_password(p_profile uuid, p_password text) returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
declare v public.profiles;
begin
  select * into v from public.profiles where id = p_profile;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.id = public.my_profile_id() then raise exception 'Gunakan menu Ganti password untuk akun sendiri'; end if;
  if not public.boleh_atur_akun(v) then raise exception 'Akses ditolak'; end if;
  if length(coalesce(p_password, '')) < 6 then raise exception 'Password minimal 6 karakter'; end if;
  if v.auth_uid is null then
    raise exception 'Akun ini belum pernah login. Pemilik akun membuat password sendiri saat login pertama.';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
   where id = v.auth_uid;
end $$;

create or replace function public.email_baru(p_prefix text) returns text
language sql volatile as $$
  select p_prefix || to_char(now(), 'YYMMDDHH24MISS') || substr(md5(random()::text), 1, 4) || '@dailyreportlka.app'
$$;

-- Tambah PC (p_id null) atau ubah nama / pindah toko / aktif-nonaktif. MT, Trainer, Sales sesuai cakupan.
create or replace function public.simpan_pc(p_id uuid, p_nama text, p_store int, p_aktif boolean default true) returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare
  v public.profiles;
  v_id uuid;
begin
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama PC wajib diisi'; end if;
  if not exists (select 1 from public.stores where id = p_store and aktif) then raise exception 'Toko tidak ditemukan'; end if;
  if not public.can_manage_store(p_store) then raise exception 'Toko ini di luar cakupan kamu'; end if;
  if p_id is null then
    insert into public.profiles (nama, role, store_id, email)
    values (trim(p_nama), 'pc', p_store, public.email_baru('pc'))
    returning id into v_id;
    return v_id;
  end if;
  select * into v from public.profiles where id = p_id;
  if v.id is null or v.role <> 'pc' then raise exception 'Akun PC tidak ditemukan'; end if;
  if not public.can_manage_store(v.store_id) then raise exception 'PC ini di luar cakupan kamu'; end if;
  if not coalesce(p_aktif, true) and v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles
     set nama = trim(p_nama), store_id = p_store, aktif = coalesce(p_aktif, true),
         auth_uid = case when coalesce(p_aktif, true) then auth_uid end
   where id = p_id;
  return p_id;
end $$;

-- Tambah toko (p_id null) atau ubah nama / aktif-nonaktif. Pindah area hanya MT.
create or replace function public.simpan_toko(p_id int, p_nama text, p_area int, p_aktif boolean default true) returns int
language plpgsql security definer set search_path = public as $$
declare
  v public.stores;
  v_id int;
begin
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama toko wajib diisi'; end if;
  if not public.is_pengubah() or not public.in_cakupan(p_area) then raise exception 'Area ini di luar cakupan kamu'; end if;
  if p_id is null then
    insert into public.stores (nama, area_id) values (trim(p_nama), p_area) returning id into v_id;
    return v_id;
  end if;
  select * into v from public.stores where id = p_id;
  if v.id is null then raise exception 'Toko tidak ditemukan'; end if;
  if not public.can_manage_store(p_id) then raise exception 'Toko ini di luar cakupan kamu'; end if;
  if v.area_id <> p_area and not public.is_mt() then raise exception 'Pindah area hanya oleh Manajer Trainer'; end if;
  if not coalesce(p_aktif, true) and exists (select 1 from public.profiles where store_id = p_id and role = 'pc' and aktif) then
    raise exception 'Pindahkan atau nonaktifkan PC di toko ini terlebih dahulu';
  end if;
  update public.stores set nama = trim(p_nama), area_id = p_area, aktif = coalesce(p_aktif, true) where id = p_id;
  return p_id;
end $$;

-- MT: tambah / ubah akun Trainer atau Sales
create or replace function public.simpan_atasan(p_id uuid, p_nama text, p_role text, p_aktif boolean default true) returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare v public.profiles; v_id uuid;
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  if p_role not in ('trainer', 'sales') then raise exception 'Jabatan harus Trainer atau Sales'; end if;
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama wajib diisi'; end if;
  if p_id is null then
    insert into public.profiles (nama, role, email) values (trim(p_nama), p_role, public.email_baru(p_role)) returning id into v_id;
    return v_id;
  end if;
  select * into v from public.profiles where id = p_id;
  if v.id is null or v.role not in ('trainer', 'sales') then raise exception 'Akun tidak ditemukan'; end if;
  if v.role <> p_role then raise exception 'Jabatan tidak bisa diubah. Buat akun baru.'; end if;
  if not coalesce(p_aktif, true) and v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set nama = trim(p_nama), aktif = coalesce(p_aktif, true),
         auth_uid = case when coalesce(p_aktif, true) then auth_uid end
   where id = p_id;
  return p_id;
end $$;

-- MT: tambah / ubah area dan Sales pemiliknya. Area baru otomatis mendapat list produk induk.
create or replace function public.simpan_area(p_id int, p_nama text, p_sales uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_id int;
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama area wajib diisi'; end if;
  if p_sales is not null and not exists (select 1 from public.profiles where id = p_sales and role = 'sales') then
    raise exception 'Sales tidak ditemukan';
  end if;
  if p_id is null then
    insert into public.areas (nama, sales_id) values (trim(p_nama), p_sales) returning id into v_id;
    return v_id;
  end if;
  update public.areas set nama = trim(p_nama), sales_id = p_sales where id = p_id;
  return p_id;
end $$;

-- MT: penugasan Trainer -> Sales (p_trainer null = lepas)
create or replace function public.set_trainer_sales(p_sales uuid, p_trainer uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  if p_trainer is null then
    delete from public.trainer_sales where sales_id = p_sales;
    return;
  end if;
  if not exists (select 1 from public.profiles where id = p_trainer and role = 'trainer') then raise exception 'Trainer tidak ditemukan'; end if;
  insert into public.trainer_sales (sales_id, trainer_id) values (p_sales, p_trainer)
  on conflict (sales_id) do update set trainer_id = excluded.trainer_id;
  perform public.kpi_awal(p_trainer, public.today_wib());
end $$;

-- MT: produk baru dari pusat, ditambahkan ke SEMUA area sekaligus (dan ke list induk untuk area baru)
create or replace function public.produk_semua_area(p_tipe text, p_nama text, p_grup text, p_harga bigint, p_fokus text)
returns int
language plpgsql security definer set search_path = public as $$
declare v_kode text; n int;
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama produk wajib diisi'; end if;
  select kode into v_kode from public.produk_master where tipe = p_tipe and lower(nama) = lower(trim(p_nama));
  if v_kode is null then
    insert into public.produk_master (tipe, nama, grup, harga, fokus, urutan)
    values (p_tipe, trim(p_nama), p_grup, p_harga, nullif(trim(coalesce(p_fokus, '')), ''),
            coalesce((select max(urutan) + 1 from public.produk_master where tipe = p_tipe), 1))
    returning kode into v_kode;
  end if;
  insert into public.products (area_id, kode, tipe, nama, grup, harga, fokus, urutan)
  select a.id, m.kode, m.tipe, m.nama, m.grup, m.harga, m.fokus, m.urutan
    from public.areas a cross join public.produk_master m
   where m.kode = v_kode
     and not exists (select 1 from public.products x where x.area_id = a.id and (x.kode = m.kode or (x.tipe = m.tipe and lower(x.nama) = lower(m.nama))));
  get diagnostics n = row_count;
  return n;
end $$;

-- Area di cakupan akun (untuk pilihan di menu Kelola)
-- Tandai / lepas tipe fokus satu produk (kode) di semua area wilayah Trainer. Khusus MT dan Trainer itu sendiri.
-- Label = label fokus yang sudah dipakai tipe yang sama di area itu, atau nama tipe tanpa varian ("A6X [4/64]" -> "A6X").
create or replace function public.atur_fokus(p_trainer uuid, p_kode text, p_fokus boolean) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not coalesce(public.is_mt() or (public.my_role() = 'trainer' and p_trainer = public.my_profile_id()), false) then
    raise exception 'Tipe fokus hanya diatur oleh MT atau Trainer wilayahnya';
  end if;
  update public.products p
     set fokus = case when not p_fokus then null
                      else coalesce((select q.fokus from public.products q
                                      where q.area_id = p.area_id and q.fokus is not null and q.id <> p.id
                                        and trim(split_part(q.nama, ' [', 1)) = trim(split_part(p.nama, ' [', 1)) limit 1),
                                    trim(split_part(p.nama, ' [', 1))) end
   where p.kode = p_kode
     and p.area_id in (select a.id from public.areas a join public.trainer_sales ts on ts.sales_id = a.sales_id
                        where ts.trainer_id = p_trainer);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.area_saya() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'nama', a.nama, 'aktif', a.aktif, 'sales_id', a.sales_id,
           'sales', (select nama from public.profiles where id = a.sales_id),
           'trainer_id', public.area_trainer(a.id),
           'trainer', (select nama from public.profiles where id = public.area_trainer(a.id)))
         order by a.nama), '[]'::jsonb)
    from public.areas a where a.id in (select public.area_cakupan())
$$;

-- Toko di cakupan akun beserta PC-nya
create or replace function public.toko_saya(p_semua boolean default false) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'nama', s.nama, 'aktif', s.aktif, 'area_id', s.area_id, 'area', a.nama,
           'sales', (select nama from public.profiles where id = a.sales_id),
           'pc', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nama', p.nama, 'aktif', p.aktif,
                                                                'sudah_daftar', p.auth_uid is not null,
                                                                'last_seen', p.last_seen, 'logged_in', p.logged_in)
                                             order by p.aktif desc, p.nama), '[]'::jsonb)
                    from public.profiles p where p.store_id = s.id and p.role = 'pc' and (p_semua or p.aktif)))
         order by a.nama, s.nama), '[]'::jsonb)
    from public.stores s join public.areas a on a.id = s.area_id
   where public.is_atasan() and a.id in (select public.area_cakupan()) and (p_semua or s.aktif)
$$;

-- ---------------------------------------------------------------------
-- 10. RPC LAPORAN PC
-- ---------------------------------------------------------------------
create or replace function public.laporan_kurang(p_pc uuid, p_tanggal date) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when not exists (select 1 from public.stok_update where store_id = public.pc_store(p_pc) and tanggal = p_tanggal)
         then 'Stok' end,
    case when not exists (select 1 from public.sales where pc_id = p_pc and tanggal = p_tanggal)
          and not exists (select 1 from public.checkins where pc_id = p_pc and tanggal = p_tanggal and modul = 'penjualan')
         then 'Penjualan (atau NOSELL)' end,
    case when not exists (select 1 from public.competitor_sales where store_id = public.pc_store(p_pc) and tanggal = p_tanggal)
         then 'MS Allbrand' end,
    case when not exists (select 1 from public.leasing_checks where pc_id = p_pc and tanggal = p_tanggal)
          and not exists (select 1 from public.checkins where pc_id = p_pc and tanggal = p_tanggal and modul = 'cek_limit')
         then 'Cek limit (atau tidak ada pengajuan)' end
  ], null)
$$;

-- PC mengirim laporan hari ini (batas 22.30 WIB)
create or replace function public.kirim_laporan(p_tanggal date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_kurang text[];
  r public.daily_reports;
begin
  if coalesce(public.my_role(), '') <> 'pc' then raise exception 'Laporan dikirim oleh PC'; end if;
  if not public.pc_jam_buka(p_tanggal) then
    raise exception 'Laporan hanya bisa dikirim hari ini sebelum 22.30 WIB.';
  end if;
  v_kurang := public.laporan_kurang(v_me, p_tanggal);
  if array_length(v_kurang, 1) > 0 then
    raise exception 'Laporan belum lengkap: %', array_to_string(v_kurang, ', ');
  end if;
  insert into public.daily_reports (pc_id, tanggal, store_id, dikirim_oleh)
  values (v_me, p_tanggal, public.my_store_id(), v_me)
  on conflict (pc_id, tanggal) do update set dikirim_pada = public.daily_reports.dikirim_pada
  returning * into r;
  return to_jsonb(r);
end $$;

-- Simpan stok toko hari ini.
--   Stok awal (pertama kali): p_items = [{"product_id": 1, "qty": 5}, ...] = hitungan fisik.
--   Sesudahnya: barang masuk p_items = [{"product_id": 1, "tambah": 3}, ...] (ditambahkan ke stok),
--   atau koreksi p_items = [{"product_id": 1, "qty": 4}, ...] (angka stok yang benar). PC, MT, Trainer, Sales.
-- Hanya produk yang berubah dicatat di riwayat.
create or replace function public.simpan_stok(p_store int, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.today_wib();
  v_awal boolean;
  v_area int := public.store_area(p_store);
  r record;
  n int := 0;
begin
  if not public.can_write_daily(p_store, v_today) then
    raise exception 'Tidak diizinkan. Stok hanya bisa diubah oleh PC tokonya atau atasan wilayahnya.';
  end if;
  select stok_awal_pada is null into v_awal from public.stores where id = p_store;
  for r in
    select p.id as product_id,
           not v_awal and d ? 'tambah' as tambah,
           case when not v_awal and d ? 'tambah'
                then coalesce(s.qty, 0) + greatest(0, least(9999, coalesce((d->>'tambah')::int, 0)))
                else greatest(-99999, least(99999, coalesce((d->>'qty')::int, coalesce(s.qty, 0)))) end as qty,
           coalesce(s.qty, 0) as lama
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) d
      join public.products p on p.id = (d->>'product_id')::int and p.area_id = v_area
      left join public.stok s on s.store_id = p_store and s.product_id = p.id
  loop
    if r.qty <> r.lama then
      perform public.ubah_stok(p_store, r.product_id, r.qty - r.lama, v_today, case when v_awal then 'awal' when r.tambah then 'masuk' else 'koreksi' end, null);
      n := n + 1;
    end if;
  end loop;
  if v_awal then
    update public.stores set stok_awal_pada = now(), stok_awal_tanggal = v_today where id = p_store;
  end if;
  insert into public.stok_update (store_id, tanggal, oleh, stok_hp, stok_iot)
  select p_store, v_today, public.my_profile_id(),
         coalesce(sum(s.qty) filter (where p.tipe = 'HP'), 0), coalesce(sum(s.qty) filter (where p.tipe = 'IOT'), 0)
    from public.stok s join public.products p on p.id = s.product_id
   where s.store_id = p_store
  on conflict (store_id, tanggal) do update
     set terakhir = now(), oleh = excluded.oleh, stok_hp = excluded.stok_hp, stok_iot = excluded.stok_iot;
  return jsonb_build_object('stok_awal', v_awal, 'berubah', n);
end $$;

-- Simpan MS Allbrand satu toko satu tanggal (mengganti isian tanggal itu saja)
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.my_profile_id();
begin
  if not public.can_write_ms(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. MS Allbrand hanya bisa diisi untuk tanggal 1 s.d. hari ini di bulan berjalan.';
  end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  insert into public.competitor_sales_detail (store_id, tanggal, brand_id, segmen, unit, diinput_oleh)
  select p_store, p_tanggal, (d->>'brand_id')::int, d->>'segmen', sum((d->>'unit')::int), v_me
    from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) d
   where coalesce((d->>'unit')::int, 0) > 0
   group by (d->>'brand_id')::int, d->>'segmen';
  insert into public.competitor_sales (store_id, tanggal, brand_id, unit, diinput_oleh, updated_at)
  select p_store, p_tanggal, b.id,
         coalesce((select sum(x.unit) from public.competitor_sales_detail x
                    where x.store_id = p_store and x.tanggal = p_tanggal and x.brand_id = b.id), 0),
         v_me, now()
    from public.competitor_brands b
   where b.aktif
  on conflict (store_id, tanggal, brand_id) do update
     set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();
end $$;

create or replace function public.hapus_ms_allbrand(p_store int, p_tanggal date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_write_ms(p_store, p_tanggal) then raise exception 'Tidak diizinkan menghapus MS Allbrand tanggal ini.'; end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  delete from public.competitor_sales where store_id = p_store and tanggal = p_tanggal;
end $$;

-- Rekap satu PC pada satu tanggal: beranda PC, detail PC untuk atasan, dan gambar laporan
create or replace function public.rekap_pc(p_pc uuid, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  v_akhir date := (date_trunc('month', p_tanggal) + interval '1 month - 1 day')::date;
  v_store int := public.pc_store(p_pc);
  v_area int := public.store_area(v_store);
  r jsonb;
begin
  if not public.can_view_pc(p_pc) then raise exception 'Akses ditolak'; end if;
  with s as (
    select x.*, public.segmen_harga(x.harga) as segmen from public.sales x
     where x.pc_id = p_pc and x.tanggal between v_bulan and p_tanggal
  ), h as (select * from s where tanggal = p_tanggal),
  ts as (  -- penjualan HP semua PC di toko (untuk MS Allbrand toko)
    select x.qty, x.tanggal, public.segmen_harga(x.harga) as segmen from public.sales x
     where x.store_id = v_store and x.tipe = 'HP' and x.tanggal between v_bulan and p_tanggal
  ),
  k as (select c.* from public.competitor_sales c where c.store_id = v_store and c.tanggal between v_bulan and p_tanggal),
  kd as (
    select d.*, b.nama as brand, b.urutan
      from public.competitor_sales_detail d join public.competitor_brands b on b.id = d.brand_id
     where d.store_id = v_store and d.tanggal = p_tanggal
  )
  select jsonb_build_object(
    'pc_id', p_pc,
    'pc', (select nama from public.profiles where id = p_pc),
    'store_id', v_store,
    'toko', (select nama from public.stores where id = v_store),
    'area_id', v_area,
    'area', (select nama from public.areas where id = v_area),
    'sales', (select p.nama from public.areas a join public.profiles p on p.id = a.sales_id where a.id = v_area),
    'trainer', (select nama from public.profiles where id = public.area_trainer(v_area)),
    'pc_lain', (select coalesce(jsonb_agg(nama order by nama), '[]'::jsonb) from public.profiles
                 where store_id = v_store and role = 'pc' and aktif and id <> p_pc),
    'libur', (select status from public.pc_day_status where pc_id = p_pc and tanggal = p_tanggal),
    'offday_sisa', (select count(*) from public.pc_day_status where pc_id = p_pc and tanggal >= p_tanggal and tanggal <= v_akhir),
    'target_harian', (select jsonb_strip_nulls(jsonb_build_object('unit', t.unit, 'value', t.value, 'fokus', t.fokus, 'iot', t.iot,
                              'oleh', (select nama from public.profiles where id = t.updated_by)))
                        from public.pc_target_harian t where t.pc_id = p_pc and t.tanggal = p_tanggal),
    'hari_akhir', extract(day from v_akhir)::int,
    'hari', jsonb_build_object(
      'unit', coalesce((select sum(qty) from h where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from h where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from h where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from h where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from h where tipe = 'IOT'), 0),
      'kompetitor', coalesce((select sum(unit) from k where tanggal = p_tanggal), 0),
      'toko_unit', coalesce((select sum(qty) from ts where tanggal = p_tanggal), 0)),
    'bulan', jsonb_build_object(
      'unit', coalesce((select sum(qty) from s where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from s where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from s where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from s where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from s where tipe = 'IOT'), 0),
      'kompetitor', coalesce((select sum(unit) from k), 0),
      'toko_unit', coalesce((select sum(qty) from ts), 0)),
    'target', (select coalesce(jsonb_object_agg(jenis, nilai), '{}'::jsonb)
                 from public.pc_targets where pc_id = p_pc and bulan = v_bulan),
    'penjualan', (select coalesce(jsonb_agg(jsonb_build_object(
                      'nama', nama_produk, 'tipe', tipe, 'qty', qty, 'subtotal', subtotal, 'kategori_user', kategori_user,
                      'metode', metode, 'cara_bayar', cara_bayar) order by created_at), '[]'::jsonb) from h),
    'nihil_penjualan', exists (select 1 from public.checkins where pc_id = p_pc and tanggal = p_tanggal and modul = 'penjualan'),
    'cek_limit', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'leasing', l.leasing, 'hasil', l.hasil,
                                                               'limit', l.limit_disetujui) order by l.created_at), '[]'::jsonb)
                    from public.leasing_checks l where l.pc_id = p_pc and l.tanggal = p_tanggal),
    'nihil_cek_limit', exists (select 1 from public.checkins where pc_id = p_pc and tanggal = p_tanggal and modul = 'cek_limit'),
    'cek_limit_bulan', (select jsonb_build_object('total', count(*), 'approve', count(*) filter (where hasil = 'Approve'),
                                                  'reject', count(*) filter (where hasil = 'Reject'))
                          from public.leasing_checks where pc_id = p_pc and tanggal between v_bulan and p_tanggal),
    'kompetitor_terisi', exists (select 1 from public.competitor_sales where store_id = v_store and tanggal = p_tanggal),
    'ms_oppo', jsonb_build_object(
      'lt3', coalesce((select sum(qty) from ts where tanggal = p_tanggal and segmen = 'lt3'), 0),
      '3to6', coalesce((select sum(qty) from ts where tanggal = p_tanggal and segmen = '3to6'), 0),
      'gt6', coalesce((select sum(qty) from ts where tanggal = p_tanggal and segmen = 'gt6'), 0)),
    'ms_detail', (select coalesce(jsonb_agg(jsonb_build_object('brand', brand, 'segmen', segmen, 'unit', unit)
                                            order by urutan, segmen), '[]'::jsonb) from kd),
    'ms_brands', (select coalesce(jsonb_agg(jsonb_build_object('nama', b.nama,
                      'todate', coalesce((select sum(c.unit) from k c where c.brand_id = b.id), 0)) order by b.urutan), '[]'::jsonb)
                    from public.competitor_brands b where b.aktif),
    'cash_unit', coalesce((select sum(qty) from h where tipe = 'HP' and metode = 'Cash'), 0),
    'kredit_unit', coalesce((select sum(qty) from h where tipe = 'HP' and metode = 'Kredit'), 0),
    'kredit_top', (select cara_bayar from h where metode = 'Kredit' group by cara_bayar order by sum(qty) desc limit 1),
    'stok_waktu', (select pertama from public.stok_update where store_id = v_store and tanggal = p_tanggal),
    'stok_update', (select terakhir from public.stok_update where store_id = v_store and tanggal = p_tanggal),
    'stok_awal_pada', (select stok_awal_pada from public.stores where id = v_store),
    'stok_kosong_fokus', (select coalesce(jsonb_agg(p.nama order by p.urutan), '[]'::jsonb)
                            from public.products p
                            left join public.stok sd on sd.product_id = p.id and sd.store_id = v_store
                           where p.area_id = v_area and p.fokus is not null and p.aktif and coalesce(sd.qty, 0) <= 0),
    'laporan', (select to_jsonb(x) from public.daily_reports x where x.pc_id = p_pc and x.tanggal = p_tanggal),
    'kurang', to_jsonb(public.laporan_kurang(p_pc, p_tanggal))
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 11. RPC BERANDA ATASAN (kartu bersama)
-- Filter: p_sales (satu Sales), p_store (satu toko), p_pc (satu PC). Semua null = seluruh cakupan.
-- ---------------------------------------------------------------------
create or replace function public.toko_filter(p_sales uuid, p_store int, p_pc uuid, p_trainer uuid default null)
returns setof int
language sql stable security definer set search_path = public as $$
  select s.id from public.stores s join public.areas a on a.id = s.area_id
   where s.aktif and public.can_view_store(s.id)
     and (p_sales is null or a.sales_id = p_sales)
     and (p_store is null or s.id = p_store)
     and (p_pc is null or s.id = public.pc_store(p_pc))
     and (p_trainer is null or a.sales_id in (select ts.sales_id from public.trainer_sales ts where ts.trainer_id = p_trainer))
$$;

create or replace function public.pc_filter(p_sales uuid, p_store int, p_pc uuid, p_trainer uuid default null)
returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
   where p.role = 'pc' and p.aktif and p.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
     and (p_pc is null or p.id = p_pc)
     and (public.my_role() <> 'pc' or p.id = public.my_profile_id())
$$;

create or replace function public.beranda(p_tanggal date, p_sales uuid default null, p_store int default null,
                                          p_pc uuid default null, p_trainer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  with toko as (select public.toko_filter(p_sales, p_store, p_pc, p_trainer) as id),
  pc as (
    select p.id, p.nama, p.store_id, (select d.status from public.pc_day_status d where d.pc_id = p.id and d.tanggal = p_tanggal) as libur,
           greatest(v_bulan, (p.created_at at time zone 'Asia/Jakarta')::date) as mulai
      from public.profiles p where p.id in (select public.pc_filter(p_sales, p_store, p_pc, p_trainer))
  ),
  s as (
    select x.* from public.sales x
     where x.tanggal between v_bulan and p_tanggal and x.store_id in (select id from toko)
       and (p_pc is null or x.pc_id = p_pc)
  ),
  h as (select * from s where tanggal = p_tanggal),
  tgt_toko as (   -- target toko; jika kosong pakai jumlah target PC di toko itu
    select t.id as store_id, j.jenis,
           coalesce((select nullif(nilai, 0) from public.store_targets st where st.store_id = t.id and st.bulan = v_bulan and st.jenis = j.jenis),
                    (select sum(pt.nilai) from public.pc_targets pt join public.profiles pp on pp.id = pt.pc_id
                      where pp.store_id = t.id and pp.aktif and pt.bulan = v_bulan and pt.jenis = j.jenis), 0) as nilai
      from toko t cross join (values ('unit'), ('value'), ('fokus'), ('iot'), ('iot_value')) j(jenis)
  ),
  bertugas as (select * from pc where libur is null),
  tgt_sales as (   -- target per Sales per jenis: target Sales jika diisi, selain itu jumlah target toko
    select x.sales_id, j.jenis,
           coalesce((select nullif(st.nilai, 0) from public.sales_targets st where st.sales_id = x.sales_id and st.bulan = v_bulan and st.jenis = j.jenis),
                    (select sum(t.nilai) from tgt_toko t join public.stores s2 on s2.id = t.store_id join public.areas a2 on a2.id = s2.area_id
                      where a2.sales_id = x.sales_id and t.jenis = j.jenis), 0) as nilai
      from (select distinct a.sales_id from public.stores st0 join public.areas a on a.id = st0.area_id
             where st0.id in (select id from toko) and a.sales_id is not null) x
     cross join (values ('unit'), ('value'), ('fokus'), ('iot'), ('iot_value')) j(jenis)
  ),
  tt_toko as (   -- toko per Trainer (lewat Sales area toko)
    select ts.trainer_id, st.id as store_id
      from public.stores st join public.areas a on a.id = st.area_id join public.trainer_sales ts on ts.sales_id = a.sales_id
     where st.id in (select id from toko)
  ),
  -- NOSELL bulan ini per PC = tanggal yang diisi PC sebagai NOSELL di kalender penjualan.
  pc_ns as (
    select pc.id, pc.store_id,
           (select count(*) from public.checkins c
             where c.pc_id = pc.id and c.modul = 'penjualan' and c.tanggal between v_bulan and p_tanggal) as nosell
      from pc
  )
  select jsonb_build_object(
    'hari', jsonb_build_object(
      'unit', coalesce((select sum(qty) from h where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from h where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from h where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from h where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from h where tipe = 'IOT'), 0)),
    'bulan', jsonb_build_object(
      'unit', coalesce((select sum(qty) from s where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from s where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from s where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from s where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from s where tipe = 'IOT'), 0)),
    'target', case when p_pc is not null
                   then (select coalesce(jsonb_object_agg(jenis, nilai), '{}'::jsonb) from public.pc_targets
                          where pc_id = p_pc and bulan = v_bulan)
                   when p_store is not null then (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb)
                           from (select jenis, sum(nilai) as total from tgt_toko group by jenis) t)
                   else (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb)
                           from (select jenis, sum(nilai) as total from tgt_sales group by jenis) t) end,
    'nosell_total', coalesce((select sum(nosell) from pc_ns), 0),
    'produktivitas', jsonb_build_object(
      'pc_bertugas', (select count(*) from bertugas),
      'pc_menjual', (select count(distinct pc_id) from h where pc_id in (select id from bertugas)),
      'pc_total', (select count(*) from pc),
      'unit_bulan', coalesce((select sum(qty) from s where tipe = 'HP'), 0)),
    'laporan', jsonb_build_object(
      'wajib', (select count(*) from bertugas),
      'sudah', (select count(*) from public.daily_reports d where d.tanggal = p_tanggal and d.pc_id in (select id from bertugas)),
      'belum', (select coalesce(jsonb_agg(jsonb_build_object('pc_id', b.id, 'pc', b.nama, 'toko', st.nama) order by st.nama, b.nama), '[]'::jsonb)
                  from bertugas b join public.stores st on st.id = b.store_id
                 where not exists (select 1 from public.daily_reports d where d.pc_id = b.id and d.tanggal = p_tanggal))),
    'stok', jsonb_build_object(
      'total', (select count(*) from toko),
      'sudah', (select count(*) from public.stok_update sd where sd.tanggal = p_tanggal and sd.store_id in (select id from toko)),
      'toko', (select coalesce(jsonb_agg(jsonb_build_object(
                   'store_id', st.id, 'toko', st.nama, 'area', a.nama, 'area_id', st.area_id,
                   'update', (select sd.terakhir from public.stok_update sd where sd.store_id = st.id and sd.tanggal = p_tanggal),
                   'pc', (select coalesce(jsonb_agg(pp.nama order by pp.nama), '[]'::jsonb) from public.profiles pp
                           where pp.store_id = st.id and pp.role = 'pc' and pp.aktif))
                 order by a.nama, st.nama), '[]'::jsonb)
                 from public.stores st join public.areas a on a.id = st.area_id where st.id in (select id from toko))),
    'per_sales', (select coalesce(jsonb_agg(x order by coalesce((x->>'unit')::numeric / nullif((x->>'target_unit')::numeric, 0), -1) desc, (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sales_id', a.sales_id,
          'sales', (select nama from public.profiles where id = a.sales_id),
          'area', string_agg(distinct a.nama, ', '),
          'trainer', (select p.nama from public.trainer_sales ts join public.profiles p on p.id = ts.trainer_id where ts.sales_id = a.sales_id),
          'unit', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                             where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'value', coalesce((select sum(subtotal) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_unit', coalesce((select nilai from tgt_sales t where t.jenis = 'unit' and t.sales_id is not distinct from a.sales_id), 0),

          'target_value', coalesce((select nilai from tgt_sales t where t.jenis = 'value' and t.sales_id is not distinct from a.sales_id), 0),

          'fokus', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.fokus is not null and aa.sales_id is not distinct from a.sales_id), 0),
          'target_fokus', coalesce((select nilai from tgt_sales t where t.jenis = 'fokus' and t.sales_id is not distinct from a.sales_id), 0),

          'iot', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                            where s.tipe = 'IOT' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_iot', coalesce((select nilai from tgt_sales t where t.jenis = 'iot' and t.sales_id is not distinct from a.sales_id), 0),

          'nosell', coalesce((select sum(n.nosell) from pc_ns n join public.stores st on st.id = n.store_id join public.areas aa on aa.id = st.area_id
                               where aa.sales_id is not distinct from a.sales_id), 0),
          'toko', count(distinct st0.id),
          'pc', (select count(*) from pc join public.stores st on st.id = pc.store_id join public.areas aa on aa.id = st.area_id
                  where aa.sales_id is not distinct from a.sales_id)) as x
          from public.stores st0 join public.areas a on a.id = st0.area_id
         where st0.id in (select id from toko)
         group by a.sales_id) y),
    'per_trainer', (select coalesce(jsonb_agg(x order by coalesce((x->>'unit')::numeric / nullif((x->>'target_unit')::numeric, 0), -1) desc, (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'trainer_id', tt.trainer_id,
          'trainer', (select nama from public.profiles where id = tt.trainer_id),
          'sales', (select string_agg(p.nama, ', ' order by p.nama) from public.trainer_sales x join public.profiles p on p.id = x.sales_id
                     where x.trainer_id = tt.trainer_id),
          'unit', coalesce((select sum(qty) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'value', coalesce((select sum(subtotal) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'fokus', coalesce((select sum(qty) from s where s.fokus is not null and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_unit', coalesce((select sum(nilai) from tgt_sales t where t.jenis = 'unit' and t.sales_id in (select sales_id from public.trainer_sales where trainer_id = tt.trainer_id)), 0),
          'target_value', coalesce((select sum(nilai) from tgt_sales t where t.jenis = 'value' and t.sales_id in (select sales_id from public.trainer_sales where trainer_id = tt.trainer_id)), 0),
          'target_fokus', coalesce((select sum(nilai) from tgt_sales t where t.jenis = 'fokus' and t.sales_id in (select sales_id from public.trainer_sales where trainer_id = tt.trainer_id)), 0),
          'iot', coalesce((select sum(qty) from s where s.tipe = 'IOT' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_iot', coalesce((select sum(nilai) from tgt_sales t where t.jenis = 'iot' and t.sales_id in (select sales_id from public.trainer_sales where trainer_id = tt.trainer_id)), 0),
          'nosell', coalesce((select sum(n.nosell) from pc_ns n where n.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'toko', (select count(*) from tt_toko where trainer_id = tt.trainer_id),
          'pc', (select count(*) from pc where pc.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id))) as x
          from (select distinct trainer_id from tt_toko) tt) y),
    'per_pc', (select coalesce(jsonb_agg(x order by coalesce((x->>'unit')::numeric / nullif((x->>'target_unit')::numeric, 0), -1) desc, (x->>'value')::numeric desc, x->>'pc'), '[]'::jsonb) from (
        select jsonb_build_object(
          'pc_id', pc.id, 'pc', pc.nama, 'store_id', pc.store_id, 'toko', st.nama, 'libur', pc.libur,
          'unit', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'value', coalesce((select sum(subtotal) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'unit_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'HP'), 0),
          'iot', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'IOT'), 0),
          'nosell', (select nosell from pc_ns where pc_ns.id = pc.id),
          'iot_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'IOT'), 0),
          'nosell_hari', exists (select 1 from public.checkins c where c.pc_id = pc.id and c.tanggal = p_tanggal and c.modul = 'penjualan'),
          'stok_hari', exists (select 1 from public.stok_update u where u.store_id = pc.store_id and u.tanggal = p_tanggal),
          'target_unit', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'unit'),
          'target_value', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'value'),
          'laporan_pada', (select dikirim_pada from public.daily_reports d where d.pc_id = pc.id and d.tanggal = p_tanggal),
          -- Keaktifan memakai aplikasi bulan ini: jumlah hari PC kirim laporan / input penjualan / tandai NOSELL
          'hari_aktif', (select count(distinct z.tgl) from (
              select d.tanggal as tgl from public.daily_reports d where d.pc_id = pc.id and d.tanggal between v_bulan and p_tanggal
              union select s.tanggal from s where s.pc_id = pc.id
              union select c.tanggal from public.checkins c where c.pc_id = pc.id and c.tanggal between v_bulan and p_tanggal) z),
          'target_iot', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'iot'),
          'last_seen', pp.last_seen, 'logged_in', pp.logged_in, 'sudah_daftar', pp.auth_uid is not null) as x
          from pc join public.stores st on st.id = pc.store_id join public.profiles pp on pp.id = pc.id) y)
  ) into r;
  return r;
end $$;

-- Kontribusi per series & tipe (tgl 1 s.d. p_tanggal)
create or replace function public.kontribusi_tipe(p_tanggal date, p_sales uuid default null, p_store int default null,
                                                  p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'grup', grup, 'nama', nama, 'unit', unit, 'value', value, 'unit_hari', unit_hari)
           order by tipe, urutan_grup, unit desc, nama), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.grup, '-') as grup, x.nama_produk as nama,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             sum(x.qty) filter (where x.tanggal = p_tanggal) as unit_hari,
             case x.grup when 'A Series' then 1 when 'Reno Series' then 2 when 'Find Series' then 3 else 9 end as urutan_grup
        from public.sales x
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or x.pc_id = p_pc)
         and public.can_view_pc(x.pc_id)
       group by 1, 2, 3, 7
    ) t
$$;

-- Kategori user (Walk-in / Databased / Online)
create or replace function public.kontribusi_kategori(p_tanggal date, p_sales uuid default null, p_store int default null,
                                                      p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('tipe', tipe, 'kategori', kategori, 'unit', unit, 'value', value,
                                               'unit_hari', unit_hari)), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.kategori_user, 'Belum diisi') as kategori,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             coalesce(sum(x.qty) filter (where x.tanggal = p_tanggal), 0) as unit_hari
        from public.sales x
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or x.pc_id = p_pc)
         and public.can_view_pc(x.pc_id)
       group by 1, 2
    ) t
$$;

-- Cash (Transfer/Tunai) / Kredit per leasing, rentang tanggal
create or replace function public.kontribusi_bayar(p_dari date, p_sampai date, p_sales uuid default null,
                                                   p_store int default null, p_pc uuid default null,
                                                   p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'metode', metode, 'cara_bayar', cara_bayar, 'unit', unit, 'value', value)
         order by tipe, metode, value desc), '[]'::jsonb)
    from (
      select s.tipe, coalesce(s.metode, '-') as metode, coalesce(s.cara_bayar, '-') as cara_bayar,
             sum(s.qty) as unit, sum(s.subtotal) as value
        from public.sales s
       where s.tanggal between p_dari and p_sampai
         and s.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or s.pc_id = p_pc)
         and public.can_view_pc(s.pc_id)
       group by 1, 2, 3
    ) x
$$;

-- Kalender penjualan satu bulan (cakupan / Sales / toko / PC)
create or replace function public.kalender_penjualan(p_bulan date, p_sales uuid default null, p_store int default null,
                                                     p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with toko as (select public.toko_filter(p_sales, p_store, p_pc, p_trainer) as id),
  pcs as (select public.pc_filter(p_sales, p_store, p_pc, p_trainer) as id),
  hari as (
    select generate_series(date_trunc('month', p_bulan)::date,
                           (date_trunc('month', p_bulan) + interval '1 month - 1 day')::date,
                           interval '1 day')::date as tanggal
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tanggal', h.tanggal,
           'unit', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                               and s.pc_id in (select id from pcs)), 0),
           'value', coalesce((select sum(subtotal) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                                and s.pc_id in (select id from pcs)), 0),
           'iot', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'IOT'
                              and s.pc_id in (select id from pcs)), 0),
           'kompetitor', coalesce((select sum(unit) from public.competitor_sales c where c.tanggal = h.tanggal
                                     and c.store_id in (select id from toko)), 0),
           'lapor', (select count(*) from public.daily_reports d where d.tanggal = h.tanggal and d.pc_id in (select id from pcs)),
           'off', p_pc is not null and exists (select 1 from public.pc_day_status d where d.tanggal = h.tanggal and d.pc_id = p_pc),
           'libur', (select d.status from public.pc_day_status d where p_pc is not null and d.tanggal = h.tanggal and d.pc_id = p_pc),
           'nosell', (select count(*) from public.checkins c where c.tanggal = h.tanggal and c.modul = 'penjualan'
                        and c.pc_id in (select id from pcs)),
           'nihil', p_pc is not null and exists (select 1 from public.checkins c where c.tanggal = h.tanggal
                                                    and c.modul = 'penjualan' and c.pc_id = p_pc)
         ) order by h.tanggal), '[]'::jsonb)
    from hari h
$$;

-- Total insentif hari ini dan estimasi gaji semua PC di cakupan (beranda MT / Trainer / Sales)
create or replace function public.ringkasan_gaji(p_tanggal date, p_sales uuid default null, p_store int default null,
                                                 p_pc uuid default null, p_trainer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p record;
  e jsonb; i jsonb;
  v_rows jsonb := '[]'::jsonb;
  t_ins numeric := 0; t_gaji numeric := 0; n int := 0;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  for p in
    select x.id, x.nama, s.nama as toko from public.profiles x join public.stores s on s.id = x.store_id
     where x.id in (select public.pc_filter(p_sales, p_store, p_pc, p_trainer))
     order by x.nama
  loop
    begin
      e := public.estimasi_gaji(p.id, p_tanggal);
      i := public.insentif_harian(p.id, p_tanggal);
    exception when others then
      continue;
    end;
    if coalesce((e->>'ada_aturan')::boolean, false) then
      n := n + 1;
      t_gaji := t_gaji + coalesce((e->>'total')::numeric, 0);
      t_ins := t_ins + coalesce((i->>'total_hp_tier')::numeric, 0) + coalesce((i->>'total_iot')::numeric, 0);
      v_rows := v_rows || jsonb_build_array(jsonb_build_object(
        'pc_id', p.id, 'pc', p.nama, 'toko', p.toko, 'tier', e->>'tier', 'gaji', (e->>'total')::numeric,
        'insentif_hari', coalesce((i->>'total_hp_tier')::numeric, 0) + coalesce((i->>'total_iot')::numeric, 0)));
    end if;
  end loop;
  return jsonb_build_object('pc', n, 'insentif_hari', round(t_ins), 'estimasi_gaji', round(t_gaji), 'rows', v_rows);
end $$;

-- MS Allbrand semua toko di cakupan dalam satu tabel: OPPO (unit HP) vs tiap brand, hari ini & todate.
create or replace function public.ms_area(p_tanggal date, p_sales uuid default null, p_store int default null,
                                          p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with toko as (select public.toko_filter(p_sales, p_store, p_pc, p_trainer) as id),
  awal as (select date_trunc('month', p_tanggal)::date as d)
  select jsonb_build_object(
    'brands', (select coalesce(jsonb_agg(nama order by urutan), '[]'::jsonb) from public.competitor_brands where aktif),
    'toko', (select coalesce(jsonb_agg(jsonb_build_object(
        'store_id', st.id, 'toko', st.nama, 'area', a.nama,
        'sales', (select nama from public.profiles where id = a.sales_id),
        'terisi', exists (select 1 from public.competitor_sales c where c.store_id = st.id and c.tanggal = p_tanggal),
        'oppo_hari', coalesce((select sum(qty) from public.sales x where x.store_id = st.id and x.tipe = 'HP'
                                and x.tanggal = p_tanggal), 0),
        'oppo_bulan', coalesce((select sum(qty) from public.sales x where x.store_id = st.id and x.tipe = 'HP'
                                 and x.tanggal between (select d from awal) and p_tanggal), 0),
        'brand_hari', (select coalesce(jsonb_object_agg(b.nama, c.unit), '{}'::jsonb)
                         from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
                        where c.store_id = st.id and c.tanggal = p_tanggal),
        'brand_bulan', (select coalesce(jsonb_object_agg(nama, unit), '{}'::jsonb) from (
                          select b.nama, sum(c.unit) as unit
                            from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
                           where c.store_id = st.id and c.tanggal between (select d from awal) and p_tanggal
                           group by b.nama) z))
        order by a.nama, st.nama), '[]'::jsonb)
      from public.stores st join public.areas a on a.id = st.area_id
     where st.id in (select id from toko))
  )
$$;

create table if not exists public.stok_kompetitor (
  store_id int not null references public.stores(id),
  brand text not null check (brand in ('VIVO','SAMSUNG','REALME','INFINIX','XIAOMI','TECNO','ITEL','OTHERS')),
  unit int not null default 0 check (unit >= 0),
  diinput_oleh uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, brand)
);
alter table public.stok_kompetitor enable row level security;
drop policy if exists stok_kompetitor_read on public.stok_kompetitor;
create policy stok_kompetitor_read on public.stok_kompetitor for select to authenticated
  using (public.can_view_store(store_id));
grant select on public.stok_kompetitor to authenticated;

-- Simpan stok kompetitor toko: p_data = {"VIVO": 12, "SAMSUNG": 8, ...}
create or replace function public.simpan_stok_kompetitor(p_store int, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if not coalesce((public.my_role() = 'pc' and p_store = public.my_store_id()) or public.can_manage_store(p_store), false) then
    raise exception 'Tidak diizinkan mengubah stok kompetitor toko ini.';
  end if;
  foreach b in array array['VIVO','SAMSUNG','REALME','INFINIX','XIAOMI','TECNO','ITEL','OTHERS'] loop
    insert into public.stok_kompetitor (store_id, brand, unit, diinput_oleh, updated_at)
    values (p_store, b, greatest(coalesce((p_data->>b)::int, 0), 0), public.my_profile_id(), now())
    on conflict (store_id, brand) do update
      set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();
  end loop;
end $$;
grant execute on function public.simpan_stok_kompetitor(int, jsonb) to authenticated;

-- Rekap stok terkini (MT & Manajer: semua area; Trainer & Sales: area cakupannya) per area Sales, per toko & per series
-- + penjualan bulan berjalan (untuk DOS di aplikasi) + stok kompetitor per toko.
-- DOS (days of stock) = stok / rata-rata jual per hari (unit tgl 1 s.d. p_tanggal / jumlah hari).
create or replace function public.rekap_stok(p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_awal date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  with x as (
    select st.area_id, st.id as store_id, p.tipe, case when p.tipe = 'IOT' then 'IoT' else p.grup end as grup, s.qty as stok, 0 as jual
      from public.stok s join public.products p on p.id = s.product_id join public.stores st on st.id = s.store_id
     where st.aktif and st.area_id in (select public.area_cakupan())
    union all
    select st.area_id, st.id, j.tipe, case when j.tipe = 'IOT' then 'IoT' else coalesce(j.grup, '-') end, 0, j.qty
      from public.sales j join public.stores st on st.id = j.store_id
     where j.tanggal between v_awal and p_tanggal and st.aktif and st.area_id in (select public.area_cakupan())
  ),
  g as (select area_id, store_id, tipe, grup, sum(stok) as stok, sum(jual) as jual from x group by 1, 2, 3, 4)
  select jsonb_build_object(
    'dari', v_awal, 'sampai', p_tanggal, 'hari', p_tanggal - v_awal + 1,
    'area', (select coalesce(jsonb_agg(jsonb_build_object(
        'area_id', a.id, 'area', a.nama,
        'sales', (select nama from public.profiles where id = a.sales_id),
        'toko', (select count(*) from public.stores where area_id = a.id and aktif),
        'toko_stok_awal', (select count(*) from public.stores where area_id = a.id and aktif and stok_awal_pada is not null),
        'rows', (select coalesce(jsonb_agg(jsonb_build_object('tipe', q.tipe, 'grup', q.grup, 'stok', q.stok, 'jual', q.jual)), '[]'::jsonb)
                   from (select tipe, grup, sum(stok) as stok, sum(jual) as jual from g where g.area_id = a.id group by 1, 2) q),
        'toko_list', (select coalesce(jsonb_agg(jsonb_build_object(
              'store_id', s.id, 'toko', s.nama,
              'pc', (select string_agg(p.nama, ', ' order by p.nama) from public.profiles p where p.role = 'pc' and p.store_id = s.id and coalesce(p.aktif, true)),
              'stok_awal', s.stok_awal_pada is not null,
              'rows', (select coalesce(jsonb_agg(jsonb_build_object('tipe', g.tipe, 'grup', g.grup, 'stok', g.stok, 'jual', g.jual)), '[]'::jsonb)
                         from g where g.store_id = s.id),
              'kompetitor', (select coalesce(jsonb_object_agg(k.brand, k.unit), '{}'::jsonb) from public.stok_kompetitor k where k.store_id = s.id),
              'kompetitor_pada', (select max(k.updated_at) from public.stok_kompetitor k where k.store_id = s.id))
            order by s.nama), '[]'::jsonb)
            from public.stores s where s.area_id = a.id and s.aktif))
      order by a.nama), '[]'::jsonb) from public.areas a where a.id in (select public.area_cakupan()))
  ) into r;
  return r;
end $$;


-- ---------------------------------------------------------------------
-- 12. EXPORT DATA (Excel) - MT / Trainer / Sales, maksimal 93 hari
-- ---------------------------------------------------------------------
create or replace function public.export_data(p_dari date, p_sampai date, p_sales uuid default null, p_store int default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  if p_sampai < p_dari then raise exception 'Tanggal akhir sebelum tanggal awal'; end if;
  if p_sampai - p_dari > 92 then raise exception 'Rentang maksimal 3 bulan (93 hari)'; end if;

  with toko as (
    select s.id, s.nama, a.nama as area, (select nama from public.profiles where id = a.sales_id) as sales
      from public.stores s join public.areas a on a.id = s.area_id
     where s.id in (select public.toko_filter(p_sales, p_store, null))
  ), pcs as (
    select p.id, p.nama, p.store_id from public.profiles p where p.role = 'pc' and p.store_id in (select id from toko)
  ), jual as (
    select x.store_id, x.pc_id, x.tanggal,
           sum(x.qty) filter (where x.tipe = 'HP') as unit_hp,
           sum(x.subtotal) filter (where x.tipe = 'HP') as value_hp,
           sum(x.qty) filter (where x.fokus is not null) as fokus,
           sum(x.qty) filter (where x.tipe = 'IOT') as unit_iot,
           sum(x.subtotal) filter (where x.tipe = 'IOT') as value_iot
      from public.sales x
     where x.store_id in (select id from toko) and x.tanggal between p_dari and p_sampai
     group by 1, 2, 3
  ), stok as (
    select st.store_id, st.tanggal, st.stok_hp, st.stok_iot
      from public.stok_update st
     where st.store_id in (select id from toko) and st.tanggal between p_dari and p_sampai
  ), ms as (
    select c.store_id, c.tanggal, sum(c.unit) as brand_lain
      from public.competitor_sales c
     where c.store_id in (select id from toko) and c.tanggal between p_dari and p_sampai
     group by 1, 2
  ), cek as (
    select l.pc_id, l.tanggal, count(*) as cek_limit, count(*) filter (where l.hasil = 'Approve') as approve
      from public.leasing_checks l
     where l.store_id in (select id from toko) and l.tanggal between p_dari and p_sampai
     group by 1, 2
  ), hari_toko as (
    select t.*, d::date as tanggal from toko t cross join generate_series(p_dari, p_sampai, interval '1 day') d
  ), hari_pc as (
    select p.id as pc_id, p.nama as pc, t.nama as toko, t.area, t.sales, d::date as tanggal
      from pcs p join toko t on t.id = p.store_id cross join generate_series(p_dari, p_sampai, interval '1 day') d
     where exists (select 1 from public.profiles x where x.id = p.id and x.aktif)
        or exists (select 1 from public.sales y where y.pc_id = p.id and y.tanggal between p_dari and p_sampai)
  )
  select jsonb_build_object(
    'harian_toko', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', h.tanggal, 'sales', h.sales, 'area', h.area, 'toko', h.nama,
        'unit_hp', coalesce((select sum(unit_hp) from jual j where j.store_id = h.id and j.tanggal = h.tanggal), 0),
        'value_hp', coalesce((select sum(value_hp) from jual j where j.store_id = h.id and j.tanggal = h.tanggal), 0),
        'fokus', coalesce((select sum(fokus) from jual j where j.store_id = h.id and j.tanggal = h.tanggal), 0),
        'unit_iot', coalesce((select sum(unit_iot) from jual j where j.store_id = h.id and j.tanggal = h.tanggal), 0),
        'value_iot', coalesce((select sum(value_iot) from jual j where j.store_id = h.id and j.tanggal = h.tanggal), 0),
        'stok_hp', st.stok_hp, 'stok_iot', st.stok_iot, 'ms_brand_lain', m.brand_lain,
        'cek_limit', coalesce((select sum(c.cek_limit) from cek c join pcs p on p.id = c.pc_id where p.store_id = h.id and c.tanggal = h.tanggal), 0))
        order by h.tanggal, h.sales, h.area, h.nama), '[]'::jsonb)
      from hari_toko h
      left join stok st on st.store_id = h.id and st.tanggal = h.tanggal
      left join ms m on m.store_id = h.id and m.tanggal = h.tanggal),
    'harian_pc', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', h.tanggal, 'sales', h.sales, 'area', h.area, 'toko', h.toko, 'pc', h.pc,
        'unit_hp', coalesce(j.unit_hp, 0), 'value_hp', coalesce(j.value_hp, 0), 'fokus', coalesce(j.fokus, 0),
        'unit_iot', coalesce(j.unit_iot, 0), 'value_iot', coalesce(j.value_iot, 0),
        'cek_limit', coalesce(c.cek_limit, 0), 'cek_approve', coalesce(c.approve, 0),
        'libur', (select ds.status from public.pc_day_status ds where ds.pc_id = h.pc_id and ds.tanggal = h.tanggal),
        'laporan', (select to_char(dr.dikirim_pada at time zone 'Asia/Jakarta', 'HH24:MI') from public.daily_reports dr
                     where dr.pc_id = h.pc_id and dr.tanggal = h.tanggal))
        order by h.tanggal, h.sales, h.toko, h.pc), '[]'::jsonb)
      from hari_pc h
      left join jual j on j.pc_id = h.pc_id and j.tanggal = h.tanggal
      left join cek c on c.pc_id = h.pc_id and c.tanggal = h.tanggal),
    'penjualan', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', x.tanggal, 'toko', t.nama, 'pc', p.nama, 'tipe', x.tipe, 'grup', x.grup, 'produk', x.nama_produk,
        'qty', x.qty, 'harga', x.harga, 'subtotal', x.subtotal, 'kategori_user', x.kategori_user,
        'metode', x.metode, 'cara_bayar', x.cara_bayar) order by x.tanggal, t.nama, p.nama, x.created_at), '[]'::jsonb)
      from public.sales x join toko t on t.id = x.store_id join public.profiles p on p.id = x.pc_id
     where x.tanggal between p_dari and p_sampai),
    -- Stok terkini per produk (saat export dibuat)
    'stok', (select coalesce(jsonb_agg(jsonb_build_object(
        'toko', t.nama, 'tipe', p.tipe, 'grup', p.grup, 'produk', p.nama, 'qty', st.qty,
        'update', to_char(st.updated_at at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI'))
        order by t.nama, p.tipe, p.urutan), '[]'::jsonb)
      from public.stok st join toko t on t.id = st.store_id join public.products p on p.id = st.product_id
     where st.qty <> 0),
    -- Riwayat perubahan stok dalam rentang tanggal
    'mutasi_stok', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', m.tanggal, 'jam', to_char(m.waktu at time zone 'Asia/Jakarta', 'HH24:MI'), 'toko', t.nama,
        'produk', p.nama, 'jenis', m.jenis, 'perubahan', m.perubahan, 'sesudah', m.sesudah,
        'oleh', (select nama from public.profiles where id = m.oleh))
        order by m.waktu), '[]'::jsonb)
      from public.stok_mutasi m join toko t on t.id = m.store_id join public.products p on p.id = m.product_id
     where m.tanggal between p_dari and p_sampai),
    'ms_allbrand', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', d.tanggal, 'toko', t.nama, 'brand', b.nama, 'segmen', d.segmen, 'unit', d.unit)
        order by d.tanggal, t.nama, b.urutan, d.segmen), '[]'::jsonb)
      from public.competitor_sales_detail d join toko t on t.id = d.store_id
      join public.competitor_brands b on b.id = d.brand_id
     where d.tanggal between p_dari and p_sampai),
    'cek_limit', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', l.tanggal, 'toko', t.nama, 'pc', p.nama, 'leasing', l.leasing, 'hasil', l.hasil, 'limit', l.limit_disetujui,
        'jam', to_char(l.created_at at time zone 'Asia/Jakarta', 'HH24:MI'))
        order by l.tanggal, t.nama, p.nama, l.created_at), '[]'::jsonb)
      from public.leasing_checks l join toko t on t.id = l.store_id join public.profiles p on p.id = l.pc_id
     where l.tanggal between p_dari and p_sampai)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 12b. HEMAT DATABASE: hapus otomatis data > 1 tahun & hapus permanen PC
-- ---------------------------------------------------------------------
create table if not exists public.bersih_log (
  id bigserial primary key,
  waktu timestamptz not null default now(),
  pemicu text,
  batas date,
  rincian jsonb
);
alter table public.bersih_log enable row level security;
drop policy if exists bersih_log_mt on public.bersih_log;
create policy bersih_log_mt on public.bersih_log for select to authenticated using (public.is_mt());

-- Hapus semua data harian/transaksi yang tanggalnya lebih tua dari 1 tahun (365 hari).
-- Master (akun, toko, area, produk, brand) dan stok terkini tidak dihapus.
-- Dijalankan otomatis setiap hari 02.00 WIB, atau oleh MT lewat menu Penyimpanan server.
create or replace function public.bersihkan_data_lama(p_pemicu text default 'jadwal') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_batas date := public.today_wib() - 365;
  v_bulan date := date_trunc('month', public.today_wib() - 365)::date;
  r jsonb := '{}'::jsonb;
  n int;
begin
  perform set_config('lka.bersih', '1', true);
  delete from public.sales where tanggal < v_batas;                     get diagnostics n = row_count; r := r || jsonb_build_object('penjualan', n);
  delete from public.checkins where tanggal < v_batas;                  get diagnostics n = row_count; r := r || jsonb_build_object('nosell', n);
  delete from public.leasing_checks where tanggal < v_batas;            get diagnostics n = row_count; r := r || jsonb_build_object('cek_limit', n);
  delete from public.daily_reports where tanggal < v_batas;             get diagnostics n = row_count; r := r || jsonb_build_object('laporan', n);
  delete from public.pc_day_status where tanggal < v_batas;             get diagnostics n = row_count; r := r || jsonb_build_object('kehadiran', n);
  delete from public.competitor_sales_detail where tanggal < v_batas;   get diagnostics n = row_count; r := r || jsonb_build_object('ms_rincian', n);
  delete from public.competitor_sales where tanggal < v_batas;          get diagnostics n = row_count; r := r || jsonb_build_object('ms', n);
  delete from public.stok_mutasi where tanggal < v_batas;               get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_stok', n);
  delete from public.stok_update where tanggal < v_batas;               get diagnostics n = row_count; r := r || jsonb_build_object('cek_stok', n);
  delete from public.store_targets where bulan < v_bulan;               get diagnostics n = row_count; r := r || jsonb_build_object('target_toko', n);
  delete from public.pc_targets where bulan < v_bulan;                  get diagnostics n = row_count; r := r || jsonb_build_object('target_pc', n);
  delete from public.pc_target_harian where tanggal < v_batas;          get diagnostics n = row_count; r := r || jsonb_build_object('target_harian', n);
  delete from public.login_log where waktu < now() - interval '365 days'; get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_login', n);
  delete from public.audit_log where waktu < now() - interval '365 days'; get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_perubahan', n);
  delete from public.bersih_log where waktu < now() - interval '365 days';
  -- KPI bulan lama: simpan bulan terakhir tiap Trainer yang masih jadi patokan
  delete from public.kpi_tier k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_potongan k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_aturan k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.insentif_produk k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.insentif_lain k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_fokus k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_gaji k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  perform set_config('lka.bersih', '', true);
  insert into public.bersih_log (pemicu, batas, rincian) values (p_pemicu, v_batas, r);
  return r || jsonb_build_object('batas', v_batas);
end $$;

revoke execute on function public.bersihkan_data_lama(text) from public, anon, authenticated;

-- Tombol "Bersihkan sekarang" untuk MT
create or replace function public.bersihkan_sekarang() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  return public.bersihkan_data_lama('manual');
end $$;

-- Hapus PERMANEN akun PC beserta semua datanya (penjualan, cek limit, laporan, kehadiran, target, login).
-- Hanya MT (semua PC) dan Trainer (PC di wilayahnya). Stok toko tidak berubah.
create or replace function public.hapus_pc_permanen(p_pc uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  v public.profiles;
  n int;
begin
  select * into v from public.profiles where id = p_pc;
  if v.id is null or v.role <> 'pc' then raise exception 'Akun PC tidak ditemukan'; end if;
  if not coalesce(public.is_mt() or (public.my_role() = 'trainer' and public.can_manage_store(v.store_id)), false) then
    raise exception 'Hapus permanen hanya oleh Manajer Trainer atau Trainer wilayahnya';
  end if;
  perform set_config('lka.bersih', '1', true);
  delete from public.sales where pc_id = p_pc;
  get diagnostics n = row_count;
  delete from public.checkins where pc_id = p_pc;
  delete from public.leasing_checks where pc_id = p_pc;
  delete from public.daily_reports where pc_id = p_pc;
  delete from public.pc_day_status where pc_id = p_pc;
  delete from public.pc_targets where pc_id = p_pc;
  delete from public.pc_target_harian where pc_id = p_pc;
  delete from public.login_log where profile_id = p_pc;
  update public.stok_mutasi set oleh = null where oleh = p_pc;
  update public.stok_update set oleh = null where oleh = p_pc;
  update public.competitor_sales set diinput_oleh = null where diinput_oleh = p_pc;
  update public.competitor_sales_detail set diinput_oleh = null where diinput_oleh = p_pc;
  update public.audit_log set oleh = null where oleh = p_pc;
  update public.sales set diinput_oleh = null where diinput_oleh = p_pc;
  update public.leasing_checks set diinput_oleh = null where diinput_oleh = p_pc;
  update public.checkins set oleh = null where oleh = p_pc;
  update public.daily_reports set dikirim_oleh = null where dikirim_oleh = p_pc;
  perform set_config('lka.bersih', '', true);
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  delete from public.profiles where id = p_pc;
  return jsonb_build_object('pc', v.nama, 'penjualan_dihapus', n);
end $$;

-- Info pembersihan untuk menu Penyimpanan server (MT)
create or replace function public.info_bersih() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_mt() then null else jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'batas', public.today_wib() - 365,
    'log', (select coalesce(jsonb_agg(to_jsonb(l) order by l.waktu desc), '[]'::jsonb)
              from (select * from public.bersih_log order by waktu desc limit 5) l)) end
$$;

-- Jadwal harian 02.00 WIB (= 19.00 UTC). Butuh ekstensi pg_cron (tersedia di Supabase).
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('lka-bersih-data-lama') where exists (select 1 from cron.job where jobname = 'lka-bersih-data-lama');
  perform cron.schedule('lka-bersih-data-lama', '0 19 * * *', $c$ select public.bersihkan_data_lama('jadwal'); $c$);
end $$;

-- ---------------------------------------------------------------------
-- 13. DATA AWAL: brand MS Allbrand & list produk induk (list produk HP & IoT NKA + insentifnya)
-- ---------------------------------------------------------------------
insert into public.competitor_brands (nama, urutan)
select * from (values ('Vivo', 1), ('Samsung', 2), ('Xiaomi', 3), ('Realme', 4), ('Infinix', 5), ('Tecno', 6),
                      ('Apple', 7), ('Itel', 8), ('Huawei', 9), ('Others', 10)) v(nama, urutan)
on conflict (nama) do nothing;

insert into public.produk_master (tipe, nama, grup, harga, fokus, urutan, insentif_awal)
select * from (values
  ('HP', 'A7 PRO 5G [6/256]', 'A Series', 7999000, 'A7 Pro', 1, 140000),
  ('HP', 'A7 PRO MAX 5G [8/256]', 'A Series', 9999000, 'A7 Pro', 2, 180000),
  ('HP', 'A6X [4/64]', 'A Series', 2299000, null, 3, 20000),
  ('HP', 'A6X [4/128]', 'A Series', 2899000, null, 4, 30000),
  ('HP', 'A6X [6/128]', 'A Series', 3599000, null, 5, 45000),
  ('HP', 'A6X [8/128]', 'A Series', 3899000, null, 6, 50000),
  ('HP', 'A6X [6/256]', 'A Series', 3999000, null, 7, 55000),
  ('HP', 'A6C [4/64]', 'A Series', 2799000, null, 8, 30000),
  ('HP', 'A6C [4/128]', 'A Series', 3199000, null, 9, 40000),
  ('HP', 'A6 [6/128]', 'A Series', 4299000, null, 10, 90000),
  ('HP', 'A6 [6/256]', 'A Series', 4799000, null, 11, 110000),
  ('HP', 'A6S [8/128]', 'A Series', 4999000, null, 12, 90000),
  ('HP', 'A6S [8/256]', 'A Series', 5499000, null, 13, 110000),
  ('HP', 'A6 PRO 4G [8/128]', 'A Series', 4599000, null, 14, 70000),
  ('HP', 'A6 PRO 4G [8/256]', 'A Series', 4999000, null, 15, 80000),
  ('HP', 'A6 PRO 5G [8/256]', 'A Series', 5299000, null, 16, 90000),
  ('HP', 'RENO 16 F 5G [8/128]', 'Reno Series', 7999000, 'Reno 16', 17, 150000),
  ('HP', 'RENO 16 F 5G [8/256]', 'Reno Series', 8699000, 'Reno 16', 18, 170000),
  ('HP', 'RENO 16 5G [8/256]', 'Reno Series', 11999000, 'Reno 16', 19, 200000),
  ('HP', 'RENO 16 5G [12/256]', 'Reno Series', 12999000, 'Reno 16', 20, 220000),
  ('HP', 'RENO 16 PRO 5G [12/256]', 'Reno Series', 14999000, 'Reno 16', 21, 250000),
  ('HP', 'RENO 15 F 5G [8/128]', 'Reno Series', 6599000, null, 22, 100000),
  ('HP', 'RENO 15 F 5G [8/256]', 'Reno Series', 7199000, null, 23, 120000),
  ('HP', 'RENO 15 F 5G [12/256]', 'Reno Series', 7899000, null, 24, 130000),
  ('HP', 'RENO 15 5G [8/256]', 'Reno Series', 9299000, null, 25, 160000),
  ('HP', 'RENO 15 5G [12/256]', 'Reno Series', 9999000, null, 26, 180000),
  ('HP', 'RENO 15 PRO MAX [12/512]', 'Reno Series', 14499000, null, 27, 220000),
  ('HP', 'FIND X10 [12/512]', 'Find Series', 20999000, null, 28, 400000),
  ('HP', 'FIND X9 [12/256]', 'Find Series', 15999000, null, 29, 220000),
  ('HP', 'FIND X9 [16/512]', 'Find Series', 17999000, null, 30, 270000),
  ('HP', 'FIND X9 PRO [16/512]', 'Find Series', 20999000, null, 31, 300000),
  ('HP', 'FIND X9S [12/256]', 'Find Series', 15499000, null, 32, 280000),
  ('HP', 'FIND X9S [12/512]', 'Find Series', 17499000, null, 33, 300000),
  ('HP', 'FIND X9 ULTRA [12/512]', 'Find Series', 25999000, null, 34, 420000),
  ('HP', 'FIND X9 ULTRA [16/1TB]', 'Find Series', 31999000, null, 35, 550000),
  ('HP', 'FIND N5 FOLD', 'Find Series', 27999000, null, 36, 500000),
  ('IOT', 'OPPO Pad 3 Matte Display', 'Pad', 8999000, null, 101, 150000),
  ('IOT', 'OPPO PAD 5 Matte Display Edition 256GB 8GB Star', 'Pad', 7999000, null, 102, 130000),
  ('IOT', 'PAD2 8+256GB', 'Pad', 6999000, null, 103, 120000),
  ('IOT', 'OPPO Pad Neo', 'Pad', 4599000, null, 104, 100000),
  ('IOT', 'PAD AIR 4+128 Purple', 'Pad', 3599000, null, 105, 100000),
  ('IOT', 'OPPO Pad SE Matte Display Edition', 'Pad', 3599000, null, 106, 100000),
  ('IOT', 'PAD AIR 4+64 GREY', 'Pad', 2999000, null, 107, 80000),
  ('IOT', 'OPPO Watch X3 OWWE261 Misty Titanium', 'Watch', 6999000, null, 108, 120000),
  ('IOT', 'OPPO Watch X3 OWWE261 Obsidian Black', 'Watch', 6499000, null, 109, 120000),
  ('IOT', 'WATCH X2 OWWE251', 'Watch', 5999000, null, 110, 100000),
  ('IOT', 'WATCH X OWWE231', 'Watch', 4999000, null, 111, 100000),
  ('IOT', 'OPPO Watch X2 Mini OWWE242', 'Watch', 4499000, null, 112, 100000),
  ('IOT', 'OPPO Watch S Silver Gleam', 'Watch', 3099000, null, 113, 80000),
  ('IOT', 'OPPO Watch S Phantom Black', 'Watch', 2999000, null, 114, 80000),
  ('IOT', 'OPPO Watch S Air Silver', 'Watch', 2999000, null, 115, 80000),
  ('IOT', 'OPPO BAND 2', 'Band', 1099000, null, 116, 50000),
  ('IOT', 'OPPO BAND (BLACK PURPLE)', 'Band', 599000, null, 117, 25000),
  ('IOT', 'OPPO Enco Clip2 Open Earbuds1 ETEN1', 'Audio', 2899000, null, 118, 50000),
  ('IOT', 'Enco X3i', 'Audio', 1799000, null, 119, 60000),
  ('IOT', 'Enco X3s True Wireless Noise Cancelling', 'Audio', 1799000, null, 120, 60000),
  ('IOT', 'OPPO Bubble VBG06', 'Audio', 1499000, null, 121, 20000),
  ('IOT', 'OPPO Enco Air5s ETEF1', 'Audio', 1299000, null, 122, 50000),
  ('IOT', 'Enco Air2 Pro', 'Audio', 1099000, null, 123, 50000),
  ('IOT', 'OPPO Enco Air5 ETEP1', 'Audio', 899000, null, 124, 40000),
  ('IOT', 'OPPO Enco Air4', 'Audio', 799000, null, 125, 30000),
  ('IOT', 'Enco Air3', 'Audio', 799000, null, 126, 30000),
  ('IOT', 'OPPO Enco Air3i True Wireless', 'Audio', 599000, null, 127, 35000),
  ('IOT', 'ENCO BUDS2', 'Audio', 399000, null, 128, 20000),
  ('IOT', 'OPPO Enco Buds3 Pro', 'Audio', 349000, null, 129, 20000),
  ('IOT', 'OPPO Enco Buds3 True Wireless Earbuds E', 'Audio', 299000, null, 130, 15000)
) as v(tipe, nama, grup, harga, fokus, urutan, insentif_awal)
on conflict (tipe, nama) do nothing;

-- Akun Manajer LKA (pengawas, hanya melihat). Membuat password sendiri saat login pertama.
insert into public.profiles (nama, role, email)
values ('ARDY YUSMINATA', 'manajer', 'manajer.ardy.yusminata@dailyreportlka.app')
on conflict (email) do nothing;

-- Akun Manajer Trainer. Buat juga di Authentication -> Users dengan email yang sama.
insert into public.profiles (nama, role, email)
values ('AKHMAD SAIFUDDIN', 'mt', 'mt@dailyreportlka.app')
on conflict (email) do nothing;

update public.profiles p set auth_uid = u.id
  from auth.users u
 where lower(u.email) = lower(p.email) and p.auth_uid is null;

select 'Daily Report LKA siap: ' || (select count(*) from public.produk_master) || ' produk induk, '
       || (select count(*) from public.competitor_brands) || ' brand, '
       || (select count(*) from public.profiles) || ' akun' as status;
