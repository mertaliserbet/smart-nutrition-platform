import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'meal_log_api.dart';
import 'manual_meal_log_page.dart';

class MealLogDetailPage extends StatefulWidget {
  const MealLogDetailPage({required this.id, this.api, super.key});
  final String id;
  final MealLogApi? api;
  @override
  State<MealLogDetailPage> createState() => _MealLogDetailPageState();
}

class _MealLogDetailPageState extends State<MealLogDetailPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  MealLogApi? _api;
  MealLog? _meal;
  String? _owner, _error;
  int _generation = 0;
  bool _busy = false, _foreground = true, _deleting = false;
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api?.session;
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _api = widget.api ?? (session == null ? null : MealLogApi(session));
    }
    if (!_authorized) {
      _clear();
    } else if (_meal == null && !_busy && _error == null) {
      _load();
    }
  }

  void _clear() {
    ++_generation;
    _meal = null;
    _error = null;
    _busy = _deleting;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_clear);
    if (_authorized) _load();
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized || _api == null || _busy) return;
    final generation = ++_generation;
    setState(() {
      _meal = null;
      _error = null;
      _busy = true;
    });
    try {
      final meal = await _api!.get(widget.id);
      if (mounted && _authorized && generation == _generation) {
        setState(() => _meal = meal);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is MealLogApiException
              ? error.message
              : 'Öğün yüklenemedi.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (_meal == null || _busy || !_authorized) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManualMealLogPage(api: _api, initial: _meal),
      ),
    );
    if (!mounted || !_authorized) return;
    if (changed == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Öğün güncellendi.')));
    }
    await _load();
  }

  Future<void> _delete() async {
    if (_meal == null || _busy || !_authorized) return;
    final owner = _owner;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Öğün silinsin mi?'),
        content: const Text('Bu öğün geçmişinizden kaldırılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        !_authorized ||
        owner != _owner ||
        _busy) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _deleting = true;
    });
    try {
      await _api!.delete(widget.id);
      if (mounted && _authorized && generation == _generation) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(() {
          _meal = null;
          _error =
              '${error is MealLogApiException ? error.message : 'Silme işlemi doğrulanamadı.'} Yeniden işlem yapmadan önce durumu yenileyin.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
        if (_authorized && generation != _generation) await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Öğün detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_authorized)
            const Text('Öğün bilgileri gizlendi. Oturumunuzu kontrol edin.')
          else ...[
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Öğün işlemi sürüyor',
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_meal case final meal?) ...[
              Text(
                mealTypeLabels[meal.mealType]!,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(formatMealLogTime(meal.consumedAt)),
              for (final item in meal.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final entry in {
                          'Miktar': (item.quantityGrams, 'g'),
                          'Kalori': (item.caloriesKcal, 'kcal'),
                          'Protein': (item.proteinGrams, 'g'),
                          'Karbonhidrat': (item.carbsGrams, 'g'),
                          'Yağ': (item.fatGrams, 'g'),
                        }.entries)
                          Text(
                            '${entry.key}: ${entry.value.$1 == null ? 'Belirtilmemiş' : '${entry.value.$1} ${entry.value.$2}'}',
                          ),
                        if (item.isEstimated)
                          const Text('Tahmini besin değerleri'),
                      ],
                    ),
                  ),
                ),
              if (meal.note != null) Text('Not: ${meal.note}'),
              if (meal.canEdit)
                FilledButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Düzenle'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Öğünü sil'),
              ),
            ],
            TextButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Durumu yenile'),
            ),
          ],
        ],
      ),
    ),
  );
}

String formatMealLogTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day}.${local.month}.${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
