import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations_extensions.dart';
import 'structure.dart';

class StructureView extends StatefulWidget {
  const StructureView({
    super.key,
    required this.structure,
    this.onSelection,
    this.initialSelection = const [],
  });
  final MolecularStructure structure;
  final ValueChanged<List<int>>? onSelection;
  final List<int> initialSelection;
  @override
  State<StructureView> createState() => _StructureViewState();
}

class _StructureViewState extends State<StructureView> {
  double rx = .2, ry = .2, zoom = 1, startZoom = 1;
  late final selected = widget.initialSelection.toSet();
  void select(int i, bool value) {
    setState(() {
      if (value) {
        selected.add(i);
      } else {
        selected.remove(i);
      }
    });
    widget.onSelection?.call(selected.toList()..sort());
  }

  Future<void> choose() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SizedBox(
          height: MediaQuery.sizeOf(c).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.l10n.filesSelect,
                        style: Theme.of(c).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(c).closeButtonTooltip,
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.structure.atoms.length,
                  itemBuilder: (_, i) {
                    final a = widget.structure.atoms[i];
                    return CheckboxListTile(
                      title: Text('${a.element} · ${a.source}'),
                      subtitle: a.group.isEmpty ? null : Text(a.group),
                      value: selected.contains(i),
                      onChanged: (v) {
                        select(i, v == true);
                        update(() {});
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atoms = widget.structure.atoms;
    final distance = selected.length == 2
        ? atoms[selected.first].distance(atoms[selected.last])
        : null;
    final l = context.l10n;
    Widget action(IconData icon, String label, VoidCallback callback) =>
        IconButton(tooltip: label, onPressed: callback, icon: Icon(icon));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${atoms.length} · Å',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        AspectRatio(
          aspectRatio: 1.15,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Semantics(
                label: l.filesStructure,
                child: GestureDetector(
                  onScaleStart: (_) => startZoom = zoom,
                  onScaleUpdate: (d) => setState(() {
                    zoom = (startZoom * d.scale).clamp(.4, 3);
                    ry += d.focalPointDelta.dx / 100;
                    rx += d.focalPointDelta.dy / 100;
                  }),
                  child: CustomPaint(
                    painter: _MoleculePainter(
                      widget.structure,
                      rx,
                      ry,
                      zoom,
                      selected,
                      Theme.of(context).colorScheme,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          children: [
            action(
              LucideIcons.rotateCcw,
              l.filesReset,
              () => setState(() {
                rx = .2;
                ry = .2;
                zoom = 1;
              }),
            ),
            action(
              LucideIcons.rotateCcw,
              l.filesRotateLeft,
              () => setState(() => ry -= .25),
            ),
            action(
              LucideIcons.rotateCw,
              l.filesRotateRight,
              () => setState(() => ry += .25),
            ),
            action(
              LucideIcons.plus,
              l.filesZoomIn,
              () => setState(() => zoom = (zoom * 1.15).clamp(.4, 3)),
            ),
            action(
              LucideIcons.minus,
              l.filesZoomOut,
              () => setState(() => zoom = (zoom / 1.15).clamp(.4, 3)),
            ),
            action(LucideIcons.mousePointer2, l.filesSelect, choose),
            action(LucideIcons.ruler, l.filesMeasure, choose),
          ],
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            distance == null
                ? selected.isEmpty
                      ? l.filesNoSelection
                      : selected
                            .map((i) => '${atoms[i].element}${atoms[i].source}')
                            .join(', ')
                : '${atoms[selected.first].source} – ${atoms[selected.last].source} · ${distance.toStringAsFixed(3)} Å',
          ),
        ),
        if (widget.structure.inferred)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.filesInferredBonds,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l.filesFirstModel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _MoleculePainter extends CustomPainter {
  _MoleculePainter(
    this.structure,
    this.rx,
    this.ry,
    this.zoom,
    Set<int> selected,
    this.colors,
  ) : selected = Set.of(selected);
  final MolecularStructure structure;
  final double rx, ry, zoom;
  final Set<int> selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final atoms = structure.atoms;
    var minX = double.infinity,
        minY = double.infinity,
        minZ = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (final a in atoms) {
      minX = math.min(minX, a.x);
      maxX = math.max(maxX, a.x);
      minY = math.min(minY, a.y);
      maxY = math.max(maxY, a.y);
      minZ = math.min(minZ, a.z);
      maxZ = math.max(maxZ, a.z);
    }
    final cx = (minX + maxX) / 2,
        cy = (minY + maxY) / 2,
        cz = (minZ + maxZ) / 2;
    final extent = math.max(
      2.0,
      math.sqrt(
        math.pow(maxX - minX, 2) +
            math.pow(maxY - minY, 2) +
            math.pow(maxZ - minZ, 2),
      ),
    );
    final scale = math.min(size.width, size.height) * .75 / extent * zoom;
    final points = atoms.map((a) {
      final x = a.x - cx, y = a.y - cy, z = a.z - cz;
      final xx = x * math.cos(ry) + z * math.sin(ry),
          zz = -x * math.sin(ry) + z * math.cos(ry);
      return (
        Offset(
          size.width / 2 + xx * scale,
          size.height / 2 - (y * math.cos(rx) - zz * math.sin(rx)) * scale,
        ),
        y * math.sin(rx) + zz * math.cos(rx),
      );
    }).toList();
    final bond = Paint()
      ..color = colors.outline
      ..strokeWidth = (scale * .075).clamp(1, 4)
      ..strokeCap = StrokeCap.round;
    for (final pair in structure.bonds) {
      canvas.drawLine(points[pair.$1].$1, points[pair.$2].$1, bond);
    }
    final order = List.generate(atoms.length, (i) => i)
      ..sort((a, b) => points[a].$2.compareTo(points[b].$2));
    for (final i in order) {
      final a = atoms[i], p = points[i].$1;
      final radius = (scale * (a.element == 'H' ? 0.15 : 0.25))
          .clamp(2, 18)
          .toDouble();
      final color = switch (a.element) {
        'O' => colors.error,
        'N' => colors.primary,
        'H' => colors.surfaceContainerHighest,
        _ => colors.onSurfaceVariant,
      };
      canvas.drawCircle(p, radius, Paint()..color = color);
      if (selected.contains(i)) {
        canvas.drawCircle(
          p,
          radius + 4,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MoleculePainter old) => true;
}
