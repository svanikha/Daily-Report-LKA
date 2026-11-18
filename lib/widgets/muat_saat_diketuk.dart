import 'package:flutter/material.dart';

/// Hemat egress: kartu berat (kontribusi, estimasi gaji) baru mengambil data dari server saat diketuk.
/// Kartu yang sudah dibuka tetap terbuka selama aplikasi berjalan ([id] diingat).
class MuatSaatDiketuk extends StatefulWidget {
  final String id;
  final String judul;
  final IconData icon;
  final WidgetBuilder builder;
  const MuatSaatDiketuk({super.key, required this.id, required this.judul, required this.icon, required this.builder});

  static final Set<String> _terbuka = {};

  @override
  State<MuatSaatDiketuk> createState() => _MuatSaatDiketukState();
}

class _MuatSaatDiketukState extends State<MuatSaatDiketuk> {
  bool get _buka => MuatSaatDiketuk._terbuka.contains(widget.id);

  @override
  Widget build(BuildContext context) {
    if (_buka) return widget.builder(context);
    return Card(
      child: ListTile(
        leading: Icon(widget.icon, color: Theme.of(context).colorScheme.primary),
        title: Text(widget.judul, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Ketuk untuk menampilkan'),
        trailing: const Icon(Icons.expand_more),
        onTap: () => setState(() => MuatSaatDiketuk._terbuka.add(widget.id)),
      ),
    );
  }
}
