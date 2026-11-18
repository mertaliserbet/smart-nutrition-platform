import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import 'personal_nutrition_target_api.dart';

class PersonalNutritionTargetPage extends StatefulWidget {
  const PersonalNutritionTargetPage({this.api, super.key});
  final PersonalNutritionTargetApi? api;
  @override
  State<PersonalNutritionTargetPage> createState() =>
      _PersonalNutritionTargetPageState();
}

class _PersonalNutritionTargetPageState
    extends State<PersonalNutritionTargetPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final f in personalTargetFields) f.key: TextEditingController(),
  };
  AuthSession? _session;
  PersonalNutritionTargetApi? _api;
  PersonalNutritionTargetResponse? _initial;
  String? _owner, _error;
  int _revision = 0;
  bool _loading = false,
      _saving = false,
      _changedOwner = false,
      _blocked = false,
      _completed = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _authorized =>
      !_changedOwner &&
      _foreground &&
      _session?.isAuthenticated == true &&
      _owner != null &&
      _session?.user?.id == _owner;
  bool get _locked =>
      !_authorized ||
      _loading ||
      _saving ||
      _blocked ||
      _completed ||
      _initial == null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api?.session;
    if (_owner != null &&
        (!identical(session, _session) || session?.user?.id != _owner)) {
      ++_revision;
      _changedOwner = true;
      _initial = null;
      _error = null;
      _loading = false;
      for (final f in _fields.values) {
        f.clear();
      }
    }
    _session = session;
    _owner ??= session?.user?.id;
    _api =
        widget.api ??
        (session == null ? null : PersonalNutritionTargetApi(session));
    if (_authorized &&
        _initial == null &&
        !_loading &&
        !_saving &&
        _error == null) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground && _loading) {
        ++_revision;
        _loading = false;
      }
    });
    if (_authorized &&
        _initial == null &&
        !_loading &&
        !_saving &&
        !_completed &&
        _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized || _api == null || _saving || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _initial = null;
      _error = null;
      _blocked = false;
    });
    for (final f in _fields.values) {
      f.clear();
    }
    try {
      final response = await _api!.get();
      if (!mounted || !_authorized || revision != _revision) return;
      setState(() {
        _initial = response;
        for (final entry in response.values.entries) {
          _fields[entry.key]!.text =
              entry.value
                  ?.toString()
                  .replaceFirst(RegExp(r'\.0$'), '')
                  .replaceAll('.', ',') ??
              '';
        }
      });
    } catch (error) {
      if (mounted && _authorized && revision == _revision) {
        setState(
          () => _error = error is PersonalNutritionTargetApiException
              ? error.message
              : 'Hedefler yüklenemedi. Lütfen yeniden deneyin.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_locked || !_form.currentState!.validate()) return;
    final changes = <String, num?>{};
    for (final f in personalTargetFields) {
      final text = _fields[f.key]!.text.trim();
      final value = text.isEmpty ? null : num.parse(text.replaceAll(',', '.'));
      if (value != _initial!.values[f.key]) changes[f.key] = value;
    }
    if (changes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Değişiklik bulunmuyor.')));
      return;
    }
    FocusScope.of(context).unfocus();
    final owner = _owner;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api!.patch(changes);
      if (!mounted ||
          _changedOwner ||
          owner != _owner ||
          _session?.user?.id != owner) {
        return;
      }
      _completed = true;
      if (_authorized) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && !_changedOwner && owner == _owner) {
        setState(() {
          _error = error is PersonalNutritionTargetApiException
              ? error.message
              : 'Hedeflerin kaydedilme sonucu doğrulanamadı.';
          _blocked =
              error is! PersonalNutritionTargetApiException || error.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Günlük hedeflerim')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Kişisel günlük hedefler',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Alanlar bağımsızdır. Bir hedefi kaldırmak için alanı boş bırakın. Bunlar otomatik beslenme önerisi değildir.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Atanmış diyetisyen programının tanımlı kalori ve su hedefleri Dashboard’da önceliklidir. Buradaki düzenleme programınızı değiştirmez.',
                ),
                if (!_authorized)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Hedefleri görmek için oturumunuz doğrulanmalıdır. Hesap değiştiyse bu ekranı kapatıp yeniden açın.',
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Kişisel hedefler yükleniyor',
                    ),
                  ),
                if (_authorized && _initial != null)
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        for (final f in personalTargetFields)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: TextFormField(
                              key: ValueKey(f.key),
                              controller: _fields[f.key],
                              enabled: !_locked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '${f.label} (${f.unit}/gün)',
                                hintText: 'Henüz hedef belirlenmedi',
                                border: const OutlineInputBorder(),
                                errorMaxLines: 3,
                              ),
                              validator: (input) {
                                final text = input?.trim() ?? '';
                                if (text.isEmpty) return null;
                                final value = num.tryParse(
                                  text.replaceAll(',', '.'),
                                );
                                return value != null &&
                                        PersonalNutritionTargetApi.valid(
                                          value,
                                          f.maximum,
                                        )
                                    ? null
                                    : '0’dan büyük, en fazla ${f.maximum} ${f.unit} girin.';
                              },
                            ),
                          ),
                        FilledButton(
                          onPressed: _locked ? null : _save,
                          child: Text(
                            _saving ? 'Kaydediliyor…' : 'Hedefleri kaydet',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(_error!)),
                  ),
                if (_blocked)
                  const Text(
                    'İşlem sunucuda uygulanmış olabilir. Yeniden göndermeden önce hedefleri yeniden yükleyin.',
                  ),
                if (_authorized && _error != null && !_saving)
                  TextButton(
                    onPressed: _load,
                    child: const Text('Hedefleri yeniden yükle'),
                  ),
                if (_completed)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Hedefler kaydedildi · Ekranı kapat'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
