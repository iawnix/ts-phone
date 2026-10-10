import 'dart:math' as math;

class StructureAtom {
  const StructureAtom(
    this.element,
    this.x,
    this.y,
    this.z,
    this.source, {
    this.group = '',
  });
  final String element, source, group;
  final double x, y, z;
  double distance(StructureAtom b) => math.sqrt(
    math.pow(x - b.x, 2) + math.pow(y - b.y, 2) + math.pow(z - b.z, 2),
  );
}

class MolecularStructure {
  MolecularStructure(
    this.atoms,
    this.bonds, {
    this.frame = 1,
    this.inferred = false,
  });
  final List<StructureAtom> atoms;
  final List<(int, int)> bonds;
  final int frame;
  final bool inferred;
}

/// Coordinates are read as provided (Å for these formats); no geometry is
/// generated. Source atom identities survive display transforms and selection.
MolecularStructure parseStructure(Map<String, String> input) {
  final text = input['text']!, extension = input['extension']!;
  final lines = text.split(RegExp(r'\r?\n'));
  final atoms = <StructureAtom>[], bonds = <(int, int)>[];
  var frame = 1;
  void add(
    String element,
    String x,
    String y,
    String z,
    String source, [
    String group = '',
  ]) {
    final values = [x, y, z].map(double.parse).toList();
    if (values.any((v) => !v.isFinite || v.abs() > 1e8)) {
      throw const FormatException('Invalid coordinates');
    }
    if (atoms.length >= 5000) throw const FormatException('atom_limit');
    final e = element.trim();
    if (!RegExp(r'^[A-Za-z]{1,2}$').hasMatch(e)) {
      throw const FormatException('Invalid element');
    }
    atoms.add(
      StructureAtom(
        e[0].toUpperCase() + e.substring(1).toLowerCase(),
        values[0],
        values[1],
        values[2],
        source,
        group: group,
      ),
    );
  }

  if (extension == 'xyz') {
    final count = int.parse(lines.first.trim());
    if (count < 1 || count > 5000 || lines.length < count + 2) {
      throw const FormatException('Invalid XYZ');
    }
    for (var i = 0; i < count; i++) {
      final row = lines[i + 2].trim().split(RegExp(r'\s+'));
      if (row.length < 4) throw const FormatException('Invalid XYZ atom');
      add(row[0], row[1], row[2], row[3], '${i + 1}');
    }
  } else if (extension == 'mol' || extension == 'sdf') {
    if (lines.length < 4 || lines[3].contains('V3000')) {
      throw const FormatException('Unsupported MOL version');
    }
    final count = int.parse(lines[3].substring(0, 3).trim()),
        bc = int.parse(lines[3].substring(3, 6).trim());
    if (count < 1 ||
        count > 5000 ||
        bc < 0 ||
        bc > 20000 ||
        lines.length < 4 + count + bc) {
      throw const FormatException('Invalid MOL');
    }
    for (var i = 0; i < count; i++) {
      final row = lines[i + 4];
      add(
        row.substring(31, 34),
        row.substring(0, 10),
        row.substring(10, 20),
        row.substring(20, 30),
        '${i + 1}',
      );
    }
    for (var i = 0; i < bc; i++) {
      final row = lines[i + 4 + count];
      final a = int.parse(row.substring(0, 3).trim()) - 1,
          b = int.parse(row.substring(3, 6).trim()) - 1;
      if (a < 0 || b < 0 || a >= count || b >= count) {
        throw const FormatException('Invalid MOL bond');
      }
      bonds.add((a, b));
    }
  } else if (extension == 'pdb') {
    final serials = <String, int>{};
    for (final row in lines) {
      if (row.startsWith('MODEL ')) {
        frame = int.tryParse(row.substring(6).trim()) ?? 1;
      }
      if (row.startsWith('ENDMDL')) break;
      if (row.startsWith('ATOM  ') || row.startsWith('HETATM')) {
        if (row.length < 54) throw const FormatException('Invalid PDB atom');
        final alt = row.substring(16, 17);
        if (alt != ' ' && alt != 'A') continue;
        final atomName = row.substring(12, 16);
        final explicit = row.length >= 78 ? row.substring(76, 78).trim() : '';
        final element = explicit.isNotEmpty
            ? explicit
            : (atomName[0] == ' ' || RegExp(r'[0-9]').hasMatch(atomName[0])
                  ? atomName
                        .trim()
                        .replaceAll(RegExp(r'[0-9]'), '')
                        .substring(0, 1)
                  : atomName.substring(0, 2).trim());
        final serial = row.substring(6, 11).trim();
        serials[serial] = atoms.length;
        add(
          element,
          row.substring(30, 38),
          row.substring(38, 46),
          row.substring(46, 54),
          serial,
          row.substring(17, 27).trim(),
        );
      }
    }
    for (final row in lines.where((x) => x.startsWith('CONECT'))) {
      final ids = <String>[];
      for (var p = 6; p + 5 <= row.length; p += 5) {
        ids.add(row.substring(p, p + 5).trim());
      }
      if (ids.isEmpty) continue;
      final a = serials[ids.first];
      if (a == null) continue;
      for (final id in ids.skip(1)) {
        final b = serials[id];
        if (b != null && b > a) bonds.add((a, b));
      }
    }
  } else if (extension == 'cif' || extension == 'mmcif') {
    final tokens = _cifTokens(text);
    var i = 0;
    while (i < tokens.length) {
      if (tokens[i++] != 'loop_') continue;
      final fields = <String>[];
      while (i < tokens.length && tokens[i].startsWith('_')) {
        fields.add(tokens[i++]);
      }
      if (fields.isEmpty) continue;
      final isAtoms = fields.contains('_atom_site.Cartn_x');
      String value(List<String> row, String key, [String fallback = '']) {
        final index = fields.indexOf('_atom_site.$key');
        return index < 0 ? fallback : row[index];
      }

      while (i < tokens.length &&
          !tokens[i].startsWith('_') &&
          tokens[i] != 'loop_' &&
          !tokens[i].startsWith('data_') &&
          tokens[i] != 'stop_') {
        if (i + fields.length > tokens.length) {
          throw const FormatException('Incomplete CIF loop');
        }
        final row = tokens.sublist(i, i + fields.length);
        i += fields.length;
        if (!isAtoms) continue;
        final model = value(row, 'pdbx_PDB_model_num', '1'),
            alt = value(row, 'label_alt_id', '.');
        if (model != '1' || !{'.', '?', 'A'}.contains(alt)) continue;
        add(
          value(row, 'type_symbol'),
          value(row, 'Cartn_x'),
          value(row, 'Cartn_y'),
          value(row, 'Cartn_z'),
          value(row, 'id', '${atoms.length + 1}'),
          '${value(row, 'label_asym_id')} / ${value(row, 'label_seq_id')} / ${value(row, 'label_comp_id')}',
        );
      }
    }
  } else {
    throw const FormatException('Unsupported structure');
  }
  if (atoms.isEmpty) throw const FormatException('Empty structure');
  var inferred = false;
  // Bounded spatial grid for visual connectivity. These are not bond orders.
  if (bonds.isEmpty && extension != 'mol' && extension != 'sdf') {
    inferred = true;
    const radii = {
      'H': .31,
      'C': .76,
      'N': .71,
      'O': .66,
      'F': .57,
      'P': 1.07,
      'S': 1.05,
      'Cl': 1.02,
      'Br': 1.2,
      'I': 1.39,
    };
    final grid = <(int, int, int), List<int>>{};
    for (var i = 0; i < atoms.length; i++) {
      final a = atoms[i],
          key = (
            (atoms[i].x / 4).floor(),
            (atoms[i].y / 4).floor(),
            (atoms[i].z / 4).floor(),
          );
      for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
          for (var z = -1; z <= 1; z++) {
            for (final j
                in grid[(key.$1 + x, key.$2 + y, key.$3 + z)] ?? <int>[]) {
              final other = atoms[j],
                  ar = radii[a.element],
                  br = radii[other.element];
              if (ar == null || br == null) continue;
              final distance = a.distance(other);
              if (distance > .35 && distance < ar + br + .4) bonds.add((j, i));
              if (bonds.length > 30000) {
                throw const FormatException('Dense structure');
              }
            }
          }
        }
      }
      grid.putIfAbsent(key, () => []).add(i);
    }
  }
  return MolecularStructure(atoms, bonds, inferred: inferred, frame: frame);
}

List<String> _cifTokens(String text) {
  final out = <String>[];
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '#') {
      while (i < text.length && text[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == ';' && (i == 0 || text[i - 1] == '\n')) {
      final end = text.indexOf('\n;', i + 1);
      if (end < 0) throw const FormatException('Invalid CIF text');
      out.add(text.substring(i + 1, end));
      i = end + 2;
      continue;
    }
    if (c == '"' || c == "'") {
      final start = ++i;
      while (i < text.length &&
          !(text[i] == c &&
              (i + 1 == text.length || text[i + 1].trim().isEmpty))) {
        i++;
      }
      if (i == text.length) throw const FormatException('Invalid CIF quote');
      out.add(text.substring(start, i++));
      continue;
    }
    final start = i;
    while (i < text.length && text[i].trim().isNotEmpty) {
      i++;
    }
    out.add(text.substring(start, i));
  }
  return out;
}
