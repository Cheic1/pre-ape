/// Pagina "Disegno CAD" di una planimetria: estrazione automatica di muri,
/// vani e aperture, anteprima 2D/3D, correzione di scala e altezza e
/// download DXF (AutoCAD e altri CAD, 2D + 3D) / OBJ (3D).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/planimetria/floor_plan_view.dart';
import 'package:pre_ape/features/web/web_download_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_download.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

/// Salvataggio file (iniettabile nei test; default: download del browser).
typedef SaveFile = void Function(String filename, Uint8List bytes, String mime);

class FloorPlanPage extends ConsumerStatefulWidget {
  const FloorPlanPage({super.key, required this.document, this.saveFile});

  final DocumentMeta document;
  final SaveFile? saveFile;

  @override
  ConsumerState<FloorPlanPage> createState() => _FloorPlanPageState();
}

class _FloorPlanPageState extends ConsumerState<FloorPlanPage> {
  FloorPlan? _plan;
  String? _error;
  bool _busy = false;
  bool _show3d = false;
  final _scale = TextEditingController();
  final _height = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scale.dispose();
    _height.dispose();
    super.dispose();
  }

  void _setPlan(FloorPlan plan) {
    _plan = plan;
    _error = null;
    _scale.text = plan.scaleDenominator?.toString() ?? '';
    _height.text = plan.wallHeightM.toStringAsFixed(2).replaceAll('.', ',');
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    await _run(() async {
      FloorPlan plan;
      if (widget.document.cadStats != null) {
        try {
          plan = await api.getCad(widget.document.id);
        } on NotFoundException {
          plan = await api.extractCad(widget.document.id);
        }
      } else {
        plan = await api.extractCad(widget.document.id);
      }
      if (mounted) setState(() => _setPlan(plan));
    });
  }

  Future<void> _recompute() async {
    final scale = int.tryParse(_scale.text.trim());
    final height = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    if (scale == null || scale < 20 || scale > 2000) {
      _snack('Scala non valida: inserisci il denominatore, es. 200 per 1:200.');
      return;
    }
    if (height == null || height < 2 || height > 8) {
      _snack('Altezza non valida: tra 2 e 8 m.');
      return;
    }
    await _run(() async {
      final plan = await ref.read(apiClientProvider).extractCad(
            widget.document.id,
            scaleDenominator: scale,
            wallHeightM: height,
          );
      if (mounted) setState(() => _setPlan(plan));
    });
  }

  Future<void> _download(String format) async {
    await _run(() async {
      final file =
          await ref.read(apiClientProvider).downloadCad(widget.document.id, format);
      final mime = format == 'dxf' ? 'image/vnd.dxf' : 'model/obj';
      (widget.saveFile ?? downloadBytesFile)(file.filename, file.bytes, mime);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e is UnauthorizedException) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        await ref.read(authProvider).handleUnauthorized();
        return;
      }
      final message = e.statusCode == 422
          ? e.message
          : 'Operazione non riuscita (${e.statusCode}): ${e.message}';
      if (_plan == null) {
        setState(() => _error = message);
      } else {
        _snack(message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Disegno CAD dalla planimetria'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: SafeArea(
        child: plan == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: _error != null
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.error, size: 40),
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!,
                              key: const ValueKey('cad_error'),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyLarge),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('Riprova')),
                        ])
                      : const Text('Riconoscimento di muri, vani e aperture…'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(widget.document.filename, style: AppTextStyles.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Estrazione automatica dal disegno in scala: verifica misure e '
                    'scala prima di usarla. Non sostituisce un rilievo.',
                    style: AppTextStyles.bodySmall,
                  ),
                  for (final w in plan.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(child: Text(w, style: AppTextStyles.bodySmall)),
                      ]),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Pianta 2D')),
                      ButtonSegment(value: true, label: Text('Modello 3D')),
                    ],
                    selected: {_show3d},
                    onSelectionChanged: (s) => setState(() => _show3d = s.first),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    key: const ValueKey('cad_preview'),
                    height: 360,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _show3d
                        ? FloorPlan3DView(plan: plan)
                        : CustomPaint(
                            size: Size.infinite,
                            painter: FloorPlan2DPainter(plan)),
                  ),
                  if (_show3d)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: Text('Trascina per ruotare il modello.',
                          style: AppTextStyles.bodySmall),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _StatsGrid(stats: plan.stats),
                  const SizedBox(height: AppSpacing.md),
                  Text('Correzioni', style: AppTextStyles.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cad_scale'),
                        controller: _scale,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                            labelText: 'Scala 1:', hintText: '200'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cad_height'),
                        controller: _height,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Altezza muri (m)', hintText: '2,70'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      key: const ValueKey('cad_recompute'),
                      onPressed: _busy ? null : _recompute,
                      child: const Text('Ricalcola'),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    key: const ValueKey('cad_download_dxf'),
                    onPressed: _busy ? null : () => _download('dxf'),
                    icon: const Icon(Icons.architecture),
                    label: const Text('Scarica DXF (AutoCAD, 2D + 3D)'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('cad_download_obj'),
                    onPressed: _busy ? null : () => _download('obj'),
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: const Text('Scarica OBJ (modello 3D)'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Il DXF si apre in AutoCAD, BricsCAD, ArchiCAD, Revit e LibreCAD '
                    '(da AutoCAD si può salvare in DWG). Layer: PA_MURI, PA_VANI, '
                    'PA_APERTURE_*, PA_3D_*.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final PlanStats stats;

  @override
  Widget build(BuildContext context) {
    String m(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} m';
    final items = [
      ('Superficie lorda', formatM2(stats.grossAreaM2)),
      ('Superficie netta vani', formatM2(stats.netAreaM2)),
      ('Perimetro', m(stats.perimeterM)),
      ('Vani', '${stats.rooms}'),
      ('Porte', '${stats.doors}'),
      ('Finestre', '${stats.windows} (${m(stats.windowsWidthM)})'),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (label, value) in items)
          Container(
            width: 160,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodySmall),
                Text(value, style: AppTextStyles.bodyLarge),
              ],
            ),
          ),
      ],
    );
  }
}
