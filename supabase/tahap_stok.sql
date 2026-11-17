-- =====================================================================
-- Daily Report LKA - Tahap stok: stok terkini + potong otomatis dari penjualan
-- Untuk server yang SUDAH menjalankan schema.sql versi awal. Instalasi baru cukup schema.sql.
-- SQL Editor -> New query -> tempel -> Run. Aman dijalankan ulang.
--
--   1. PC menghitung stok fisik sekali = stok awal.
--   2. Penjualan sesudahnya otomatis memotong stok (edit/hapus ikut menyesuaikan);
--      penjualan bertanggal sebelum stok awal tidak memotong stok.
--   3. Setiap hari PC cek & koreksi (barang masuk / selisih) lalu simpan.
-- Tabel stock_daily (stok salinan harian) dihapus karena boros database.
-- =====================================================================

drop table if exists public.stock_daily cascade;
drop function if exists public.keep_stock_first_input();

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
  jenis text not null check (jenis in ('awal', 'koreksi', 'jual', 'batal_jual')),
  perubahan int not null,
  sesudah int not null,
  sale_id uuid,
  oleh uuid references public.profiles(id),
  waktu timestamptz not null default now()
);
create index if not exists stok_mutasi_idx on public.stok_mutasi(store_id, tanggal);

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

do $$
declare t text;
begin
  foreach t in array array['stok', 'stok_mutasi', 'stok_update'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_view_store(store_id))', t || '_select', t);
  end loop;
end $$;

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
    raise exception 'Tidak diizinkan. PC hanya bisa update stok tokonya hari ini sebelum 22.30 WIB.';
  end if;
  select stok_awal_pada is null into v_awal from public.stores where id = p_store;
  for r in
    select p.id as product_id, greatest(-99999, least(99999, coalesce((d->>'qty')::int, 0))) as qty,
           coalesce(s.qty, 0) as lama
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) d
      join public.products p on p.id = (d->>'product_id')::int and p.area_id = v_area
      left join public.stok s on s.store_id = p_store and s.product_id = p.id
  loop
    if r.qty <> r.lama then
      perform public.ubah_stok(p_store, r.product_id, r.qty - r.lama, v_today, case when v_awal then 'awal' else 'koreksi' end, null);
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

create or replace function public.beranda(p_tanggal date, p_sales uuid default null, p_store int default null,
                                          p_pc uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  with toko as (select public.toko_filter(p_sales, p_store, p_pc) as id),
  pc as (
    select p.id, p.nama, p.store_id, (select d.status from public.pc_day_status d where d.pc_id = p.id and d.tanggal = p_tanggal) as libur
      from public.profiles p where p.id in (select public.pc_filter(p_sales, p_store, p_pc))
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
  bertugas as (select * from pc where libur is null)
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
                   else (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb)
                           from (select jenis, sum(nilai) as total from tgt_toko group by jenis) t) end,
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
    'per_sales', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sales_id', a.sales_id,
          'sales', (select nama from public.profiles where id = a.sales_id),
          'area', string_agg(distinct a.nama, ', '),
          'trainer', (select p.nama from public.trainer_sales ts join public.profiles p on p.id = ts.trainer_id where ts.sales_id = a.sales_id),
          'unit', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                             where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'value', coalesce((select sum(subtotal) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_unit', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                    where t.jenis = 'unit' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_value', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                     where t.jenis = 'value' and aa.sales_id is not distinct from a.sales_id), 0),
          'toko', count(distinct st0.id),
          'pc', (select count(*) from pc join public.stores st on st.id = pc.store_id join public.areas aa on aa.id = st.area_id
                  where aa.sales_id is not distinct from a.sales_id)) as x
          from public.stores st0 join public.areas a on a.id = st0.area_id
         where st0.id in (select id from toko)
         group by a.sales_id) y),
    'per_pc', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc, x->>'pc'), '[]'::jsonb) from (
        select jsonb_build_object(
          'pc_id', pc.id, 'pc', pc.nama, 'store_id', pc.store_id, 'toko', st.nama, 'libur', pc.libur,
          'unit', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'value', coalesce((select sum(subtotal) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'unit_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'HP'), 0),
          'iot', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'IOT'), 0),
          'target_unit', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'unit'),
          'target_value', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'value'),
          'laporan_pada', (select dikirim_pada from public.daily_reports d where d.pc_id = pc.id and d.tanggal = p_tanggal),
          'last_seen', pp.last_seen, 'logged_in', pp.logged_in, 'sudah_daftar', pp.auth_uid is not null) as x
          from pc join public.stores st on st.id = pc.store_id join public.profiles pp on pp.id = pc.id) y)
  ) into r;
  return r;
end $$;

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

select 'Tahap stok siap' as status,
       (select count(*) from information_schema.tables where table_name in ('stok', 'stok_mutasi', 'stok_update')) as tabel_baru;
