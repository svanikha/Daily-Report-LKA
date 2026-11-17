-- =====================================================================
-- Daily Report LKA - Tahap 3
--   1. Password: MT atur/reset semua akun; Trainer untuk Sales yang dipegang + PC-nya; Sales untuk PC-nya.
--   2. Stok: PC hanya menambah barang masuk (setelah stok awal); koreksi oleh atasan.
--   3. MS Allbrand satu tabel untuk semua toko di cakupan (ms_area).
--   4. NOSELL per PC, per Sales, per Trainer di beranda.
-- Jalankan SETELAH tahap_trainer.sql. Instalasi baru cukup schema.sql. Aman dijalankan ulang.
-- =====================================================================

alter table public.stok_mutasi drop constraint if exists stok_mutasi_jenis_check;
alter table public.stok_mutasi add constraint stok_mutasi_jenis_check
  check (jenis in ('awal', 'masuk', 'koreksi', 'jual', 'batal_jual'));

create or replace function public.boleh_atur_akun(v public.profiles) returns boolean
language sql stable security definer set search_path = public as $$
  select v.role <> 'mt' and (
       public.is_mt()
    or (v.role = 'pc' and public.can_manage_store(v.store_id))
    or (v.role = 'sales' and public.my_role() = 'trainer'
        and exists (select 1 from public.trainer_sales where sales_id = v.id and trainer_id = public.my_profile_id())))
$$;

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

create or replace function public.simpan_stok(p_store int, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.today_wib();
  v_awal boolean;
  v_area int := public.store_area(p_store);
  v_tambah boolean;
  r record;
  n int := 0;
begin
  if not public.can_write_daily(p_store, v_today) then
    raise exception 'Tidak diizinkan. PC hanya bisa update stok tokonya hari ini sebelum 22.30 WIB.';
  end if;
  select stok_awal_pada is null into v_awal from public.stores where id = p_store;
  v_tambah := not v_awal and public.my_role() = 'pc';
  for r in
    select p.id as product_id,
           case when v_tambah
                then coalesce(s.qty, 0) + greatest(0, least(9999, coalesce((d->>'tambah')::int, 0)))
                else greatest(-99999, least(99999, coalesce((d->>'qty')::int, coalesce(s.qty, 0)))) end as qty,
           coalesce(s.qty, 0) as lama
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) d
      join public.products p on p.id = (d->>'product_id')::int and p.area_id = v_area
      left join public.stok s on s.store_id = p_store and s.product_id = p.id
  loop
    if r.qty <> r.lama then
      perform public.ubah_stok(p_store, r.product_id, r.qty - r.lama, v_today, case when v_awal then 'awal' when v_tambah then 'masuk' else 'koreksi' end, null);
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
  tt_toko as (   -- toko per Trainer (lewat Sales area toko)
    select ts.trainer_id, st.id as store_id
      from public.stores st join public.areas a on a.id = st.area_id join public.trainer_sales ts on ts.sales_id = a.sales_id
     where st.id in (select id from toko)
  ),
  -- NOSELL bulan ini per PC: hari kerja (bukan offday/izin) tanpa penjualan HP & IoT.
  -- Hari ini dihitung hanya jika PC menandai NOSELL. Dihitung sejak PC terdaftar.
  pc_ns as (
    select pc.id, pc.store_id,
           (select count(*) from generate_series(pc.mulai, p_tanggal, interval '1 day') g(d)
             where not exists (select 1 from s where s.pc_id = pc.id and s.tanggal = g.d::date)
               and not exists (select 1 from public.pc_day_status ds where ds.pc_id = pc.id and ds.tanggal = g.d::date)
               and (g.d::date < public.today_wib()
                    or exists (select 1 from public.checkins c where c.pc_id = pc.id and c.tanggal = g.d::date and c.modul = 'penjualan'))
           ) as nosell
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
                   else (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb)
                           from (select jenis, sum(nilai) as total from tgt_toko group by jenis) t) end,
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
          'fokus', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.fokus is not null and aa.sales_id is not distinct from a.sales_id), 0),
          'target_fokus', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                     where t.jenis = 'fokus' and aa.sales_id is not distinct from a.sales_id), 0),
          'iot', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                            where s.tipe = 'IOT' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_iot', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                   where t.jenis = 'iot' and aa.sales_id is not distinct from a.sales_id), 0),
          'nosell', coalesce((select sum(n.nosell) from pc_ns n join public.stores st on st.id = n.store_id join public.areas aa on aa.id = st.area_id
                               where aa.sales_id is not distinct from a.sales_id), 0),
          'toko', count(distinct st0.id),
          'pc', (select count(*) from pc join public.stores st on st.id = pc.store_id join public.areas aa on aa.id = st.area_id
                  where aa.sales_id is not distinct from a.sales_id)) as x
          from public.stores st0 join public.areas a on a.id = st0.area_id
         where st0.id in (select id from toko)
         group by a.sales_id) y),
    'per_trainer', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'trainer_id', tt.trainer_id,
          'trainer', (select nama from public.profiles where id = tt.trainer_id),
          'sales', (select string_agg(p.nama, ', ' order by p.nama) from public.trainer_sales x join public.profiles p on p.id = x.sales_id
                     where x.trainer_id = tt.trainer_id),
          'unit', coalesce((select sum(qty) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'value', coalesce((select sum(subtotal) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'fokus', coalesce((select sum(qty) from s where s.fokus is not null and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_unit', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'unit' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_value', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'value' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_fokus', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'fokus' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'iot', coalesce((select sum(qty) from s where s.tipe = 'IOT' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_iot', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'iot' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'nosell', coalesce((select sum(n.nosell) from pc_ns n where n.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'toko', (select count(*) from tt_toko where trainer_id = tt.trainer_id),
          'pc', (select count(*) from pc where pc.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id))) as x
          from (select distinct trainer_id from tt_toko) tt) y),
    'per_pc', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc, x->>'pc'), '[]'::jsonb) from (
        select jsonb_build_object(
          'pc_id', pc.id, 'pc', pc.nama, 'store_id', pc.store_id, 'toko', st.nama, 'libur', pc.libur,
          'unit', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'value', coalesce((select sum(subtotal) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'unit_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'HP'), 0),
          'iot', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'IOT'), 0),
          'nosell', (select nosell from pc_ns where pc_ns.id = pc.id),
          'target_unit', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'unit'),
          'target_value', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'value'),
          'laporan_pada', (select dikirim_pada from public.daily_reports d where d.pc_id = pc.id and d.tanggal = p_tanggal),
          'last_seen', pp.last_seen, 'logged_in', pp.logged_in, 'sudah_daftar', pp.auth_uid is not null) as x
          from pc join public.stores st on st.id = pc.store_id join public.profiles pp on pp.id = pc.id) y)
  ) into r;
  return r;
end $$;

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

select 'Tahap 3 siap' as status;
