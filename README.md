# Daily Report LKA

Aplikasi laporan harian Product Consultant (PC) OPPO untuk toko **LKA (Local Key Account)**.
Dibangun dari kode Daily Report NKA, dengan project Supabase, repo, dan keystore terpisah
(bisa dipasang berdampingan dengan NKA). PRD: `PRD-Daily-Report-LKA.md` (folder induk).

- **Aplikasi:** Flutter (Android), package `com.oppobigsampit.daily_report_lka`, dibangun oleh GitHub Actions
- **Server:** Supabase (database & login). Tanpa foto, tanpa Firebase, tanpa notifikasi ke atasan.

## Struktur & jabatan

```
Manajer Trainer (MT) ── semua area
 └─ Trainer ── memegang beberapa Sales
     └─ Sales ── 1 area (beberapa toko)
         └─ Toko ── bisa lebih dari 1 PC
             └─ PC
```

| Data | Tingkat |
| --- | --- |
| Stok, MS Allbrand | per toko (semua PC di toko melihat angka yang sama) |

**Stok**: PC menghitung stok fisik sekali (stok awal). Sesudahnya setiap penjualan otomatis memotong stok
toko (edit/hapus ikut menyesuaikan; penjualan bertanggal sebelum stok awal tidak memotong). Setiap hari PC
cek & koreksi (barang masuk / selisih). Database hanya menyimpan stok terkini + riwayat perubahan, jadi hemat.
| Penjualan, cek limit, kirim laporan, target, estimasi gaji | per PC |
| Produk & harga | per area (Sales hanya mengubah areanya) |
| KPI & insentif | per wilayah Trainer (hanya Trainer yang mengubah) |

Laporan PC wajib: stok, penjualan (atau NOSELL), MS Allbrand, cek limit (atau "tidak ada pengajuan"),
lalu **Kirim laporan** sebelum **22.30 WIB**.

## Setup (sekali saja)

### 1. Supabase (project baru)
1. supabase.com → New project (misal `daily-report-lka`, region Singapore).
2. **SQL Editor → New query** → tempel seluruh `supabase/schema.sql` → **Run**.
   Hasil: `Daily Report LKA siap: 66 produk induk, 10 brand, 1 akun`.
3. **Authentication → Sign In / Providers → Email**: matikan **Confirm email** → Save.
4. **Authentication → Users → Add user → Create new user** untuk akun MT:
   email `mt@dailyreportlka.app`, password MT, centang **Auto Confirm User**.
   (Nama MT bisa diganti: `update profiles set nama = '...' where email = 'mt@dailyreportlka.app';`)
   Server yang dibuat sebelum 18 Nov 2026: jalankan juga `supabase/tahap_stok.sql` (stok terkini).
5. Jalankan `supabase/data_awal.sql` (Trainer, Sales, area, toko, PC), atau isi lewat aplikasi
   (MT → Kelola → Sales, Trainer & area → Toko → PC).
6. Catat **Project Settings → API**: Project URL dan anon/publishable key; **API Keys**: secret key.

### 2. GitHub
1. Buat repo baru **Daily-Report-LKA** (kosong, tanpa README) di akun yang sama, lalu push folder ini ke `main`.
2. Repo → **Settings → Secrets and variables → Actions**:
   - **Variables**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
   - **Secrets**: `SUPABASE_SECRET_KEY`
3. Build pertama membuat keystore khusus LKA di `ci/debug.keystore`. Jangan dihapus.
4. APK ada di tab **Releases** (`DailyReportLKA-v1.0.x.apk`).

## Rilis update

- Commit berisi `[tes]` → update otomatis **hanya untuk akun MT** (uji dulu).
- Commit tanpa `[tes]` → Trainer & Sales. Tambahkan `[pc]` → juga ke semua PC.
- APK lama dihapus otomatis (5 terbaru per saluran disimpan). Flutter dikunci di 3.47.9.

## Hak akses ringkas

| Fitur | MT | Trainer | Sales | PC |
| --- | --- | --- | --- | --- |
| Input & kirim laporan | | | | ✓ |
| Koreksi data PC | semua | cakupan | area | milik sendiri |
| Produk HP & IoT (per area) | semua + tambah ke semua area | cakupan | area sendiri | |
| KPI & insentif | lihat | ubah (wilayahnya) | lihat | |
| Target, offday, toko, PC | semua | cakupan | area | |
| Sales, Trainer, area, brand, storage | ✓ | | | |
| Export Excel | semua | cakupan | area | |

Toko & PC tidak dihapus, hanya dinonaktifkan (riwayat tetap). Semua perubahan produk, harga, KPI,
dan target tercatat di **Riwayat perubahan**.

## Struktur kode

```
lib/
  data/lka.dart          konstanta, HariKerja, Cakupan (filter), PcHari (konteks PC per tanggal)
  services/              session (jabatan), akun, notifikasi lokal, lampu online, update
  widgets/               kartu bersama: sell out, beranda (produktivitas, laporan, stok, peringkat),
                         kontribusi (HP/IoT, kategori user, cash/kredit, tipe), kalender, estimasi gaji
  screens/
    pc/pc_home.dart      beranda PC
    toko/                hari_pc_view, stok, penjualan, MS Allbrand, cek limit, gambar laporan
    atasan/              beranda MT/Trainer/Sales + menu Kelola
supabase/schema.sql      tabel, RLS, RPC, produk induk & KPI awal
supabase/data_awal.sql   Trainer, Sales, area, toko, PC
```
