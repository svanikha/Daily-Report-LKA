import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';

/// Area di cakupan akun (RPC area_saya).
Future<List<Map<String, dynamic>>> muatArea() async => asList(await Session.db.rpc('area_saya'));

/// Toko di cakupan akun beserta PC-nya (RPC toko_saya). [semua] = termasuk yang nonaktif.
Future<List<Map<String, dynamic>>> muatToko({bool semua = false}) async =>
    asList(await Session.db.rpc('toko_saya', params: {'p_semua': semua}));

/// Dropdown pilih area.
class AreaDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> areas;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool bolehSemua;
  final String label;
  const AreaDropdown({
    super.key,
    required this.areas,
    required this.value,
    required this.onChanged,
    this.bolehSemua = false,
    this.label = 'Area',
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.map), isDense: true),
      items: [
        if (bolehSemua) const DropdownMenuItem<int?>(value: null, child: Text('Semua area')),
        for (final a in areas)
          DropdownMenuItem<int?>(
            value: toNum(a['id']).toInt(),
            child: Text('${a['nama']}${a['sales'] != null ? ' · ${a['sales']}' : ''}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
