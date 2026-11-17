-- =====================================================================
-- Daily Report LKA - Tahap 4
--   1. NOSELL = tanggal yang diisi PC sebagai NOSELL di kalender penjualan.
--   2. Kehadiran PC: offday, izin, sakit (mengurangi sisa hari kerja / menaikkan target harian).
--   3. Status per PC (stok, IoT, NOSELL hari itu), kalender dengan jumlah PC NOSELL.
--   4. Ringkasan insentif hari ini & estimasi gaji semua PC untuk beranda atasan.
-- Jalankan SETELAH tahap_3.sql. Instalasi baru cukup schema.sql. Aman dijalankan ulang.
-- =====================================================================

alter table public.pc_day_status drop constraint if exists pc_day_status_status_check;
alter table public.pc_day_status add constraint pc_day_status_status_check
  check (status in ('offday', 'izin', 'sakit'));

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
          'iot_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'IOT'), 0),
          'nosell_hari', exists (select 1 from public.checkins c where c.pc_id = pc.id and c.tanggal = p_tanggal and c.modul = 'penjualan'),
          'stok_hari', exists (select 1 from public.stok_update u where u.store_id = pc.store_id and u.tanggal = p_tanggal),
          'target_unit', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'unit'),
          'target_value', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'value'),
          'laporan_pada', (select dikirim_pada from public.daily_reports d where d.pc_id = pc.id and d.tanggal = p_tanggal),
          'last_seen', pp.last_seen, 'logged_in', pp.logged_in, 'sudah_daftar', pp.auth_uid is not null) as x
          from pc join public.stores st on st.id = pc.store_id join public.profiles pp on pp.id = pc.id) y)
  ) into r;
  return r;
end $$;

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

select 'Tahap 4 siap' as status;
