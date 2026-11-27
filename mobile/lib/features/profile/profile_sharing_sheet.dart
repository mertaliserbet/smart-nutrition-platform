import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/onboarding_theme.dart';
import 'profile_widgets.dart';

enum ProfileSharingResult { saved, connections, findExpert }

const _sharingCopy = {
  'nutrition_plans': ('Beslenme programları', 'Planın ve program bilgilerin.'),
  'meal_logs': ('Öğün kayıtları', 'Kaydettiğin öğün ve tüketim bilgileri.'),
  'body_measurements': ('Vücut ölçümleri', 'Kilo ve vücut ölçüm kayıtların.'),
  'client_tasks': ('Danışan görevleri', 'Sana atanan görevler ve durumları.'),
  'water_logs': ('Su tüketimi', 'Su kayıtların şimdilik yalnız sende.'),
};
typedef _SharingRead = ({
  RelationshipResponse relationship,
  Map<String, DataSharingPermission> permissions,
});

class _ReadCancelled implements Exception {
  const _ReadCancelled();
}

/// Each changed category uses the existing endpoint. A partial/uncertain write
/// must be reconciled by a new read, never retried as a whole batch.
class ProfileSharingSheet extends StatefulWidget {
  const ProfileSharingSheet({
    required this.api,
    required this.session,
    required this.owner,
    required this.relationshipId,
    this.expert,
    super.key,
  });
  final DietitianApi api;
  final AuthSession session;
  final String owner, relationshipId;
  final String? expert;
  @override
  State<ProfileSharingSheet> createState() => _ProfileSharingSheetState();
}

class _ProfileSharingSheetState extends State<ProfileSharingSheet>
    with WidgetsBindingObserver {
  Map<String, DataSharingPermission> _permissions = {};
  Map<String, bool> _draft = {};
  bool _loading = false,
      _saving = false,
      _ready = false,
      _expired = false,
      _closed = false;
  String? _error;
  int _revision = 0;
  bool get _authorized =>
      !_expired &&
      widget.session.isAuthenticated &&
      widget.session.user?.id == widget.owner &&
      identical(widget.api.session, widget.session);
  bool _current(int revision) =>
      mounted && _authorized && revision == _revision;
  bool _granted(Map<String, DataSharingPermission> rows, String key) =>
      rows[key]?.isGranted == true;
  List<String> get _changes => _sharingCopy.keys
      .where((k) => (_draft[k] ?? false) != _granted(_permissions, k))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _expire() {
    _expired = true;
    ++_revision;
    _ready = false;
    _loading = false;
    _permissions = {};
    _draft = {};
    _error = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AuthSessionScope.maybeOf(context);
    if (!identical(s, widget.session) ||
        s?.isAuthenticated != true ||
        s?.user?.id != widget.owner) {
      _expire();
    }
    if (_authorized && !_ready && !_loading && !_saving && _error == null) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(_expire);
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _check(int revision) {
    if (!_current(revision)) throw const _ReadCancelled();
  }

  Future<_SharingRead> _read(int revision) async {
    _check(revision);
    final active = await widget.api.relationships(status: 'active');
    _check(revision);
    if (active.totalCount != 1 ||
        active.items.length != 1 ||
        active.items.single.id != widget.relationshipId ||
        active.items.single.status != 'active') {
      throw const DietitianApiException(
        'Diyetisyen bağlantın değişti. Bağlantılarını yeniden kontrol et.',
      );
    }
    final permissions = await widget.api.permissions(widget.relationshipId);
    _check(revision);
    if (permissions.any(
          (p) =>
              p.relationshipId != widget.relationshipId ||
              !_sharingCopy.containsKey(p.category),
        ) ||
        permissions.map((p) => p.category).toSet().length !=
            permissions.length ||
        permissions.map((p) => p.id).toSet().length != permissions.length) {
      throw const DietitianApiException.invalidResponse();
    }
    return (
      relationship: active.items.single,
      permissions: {for (final row in permissions) row.category: row},
    );
  }

  void _use(Map<String, DataSharingPermission> rows) {
    _permissions = rows;
    _draft = {for (final key in _sharingCopy.keys) key: _granted(rows, key)};
    _ready = true;
  }

  Future<void> _load() async {
    if (!_authorized || _loading || _saving) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
      _permissions = {};
      _draft = {};
    });
    try {
      final rows = await _read(revision);
      if (_current(revision)) setState(() => _use(rows.permissions));
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _error = error is DietitianApiException
              ? error.message
              : 'Paylaşım izinlerin yüklenemedi. Yeniden dene.',
        );
      }
    } finally {
      if (_current(revision)) setState(() => _loading = false);
    }
  }

  void _change(String key, bool value) {
    if (!_authorized || !_ready || _loading || _saving) return;
    // Existing water sharing may be revoked; this task never enables it.
    if (key == 'water_logs' && value && !_granted(_permissions, key)) return;
    setState(() {
      _draft[key] = value;
      _error = null;
    });
  }

  bool _sameBaseline(Map<String, DataSharingPermission> fresh) =>
      _sharingCopy.keys.every(
        (k) =>
            _permissions[k]?.id == fresh[k]?.id &&
            _granted(_permissions, k) == _granted(fresh, k),
      );
  Future<void> _save() async {
    if (!_authorized || !_ready || _loading || _saving || _changes.isEmpty) {
      return;
    }
    final revision = _revision,
        wanted = Map<String, bool>.of(_draft),
        changes = _changes;
    if (wanted['water_logs'] == true && !_granted(_permissions, 'water_logs')) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fresh = await _read(revision);
      _check(revision);
      if (!_sameBaseline(fresh.permissions)) {
        setState(() {
          _use(fresh.permissions);
          _error =
              'Paylaşım tercihlerin başka bir işlemde değişti. Güncel izinleri kontrol edip yeniden seç.';
        });
        return;
      }
      // Apply explicit revocations first; untouched categories are never written.
      changes.sort(
        (a, b) =>
            (wanted[a] == true ? 1 : 0).compareTo(wanted[b] == true ? 1 : 0),
      );
      final current = Map<String, DataSharingPermission>.of(fresh.permissions);
      for (final key in changes) {
        _check(revision);
        current[key] = await widget.api.setPermission(
          relationshipId: widget.relationshipId,
          category: key,
          isGranted: wanted[key]!,
          current: current[key],
        );
        _check(revision);
      }
      final verified = await _read(revision);
      _check(revision);
      if (changes.any(
        (key) => _granted(verified.permissions, key) != wanted[key],
      )) {
        throw const DietitianApiException(
          'Paylaşım durumu değişti. Güncel izinleri yeniden kontrol et.',
        );
      }
      setState(() => _saving = false);
      _finish(ProfileSharingResult.saved);
    } catch (error) {
      if (_current(revision)) {
        setState(() {
          _ready = false;
          _permissions = {};
          _draft = {};
          _error =
              '${error is DietitianApiException ? error.message : 'Kaydetme sonucu doğrulanamadı.'} Tekrar işlem yapmadan izinleri yeniden yükle. Daha önce tamamlanan değişiklikler korunmuş olabilir.';
        });
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  void _finish([ProfileSharingResult? result]) {
    if (_saving || _closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(21, 11, 21, 23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileSheetHeader(
                  title: 'Paylaşım tercihlerin',
                  closeLabel: 'Paylaşım tercihlerini kapat',
                  onClose: _saving ? null : _finish,
                ),
                if (!_authorized) ...[
                  const Text(
                    'Bilgileri görüntülemek için Hesabım ekranını yeniden aç.',
                    style: OnboardingTheme.hint,
                  ),
                  if (_saving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'İşlem tamamlanıyor',
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _finish,
                    style: profilePrimaryStyle(),
                    child: const Text('Hesabıma dön'),
                  ),
                ] else ...[
                  Text(
                    '${profileGivenName(widget.expert).isEmpty ? 'Diyetisyenin' : profileGivenName(widget.expert)} ile hangi bilgileri paylaşacağını sen seç.',
                    style: OnboardingTheme.hint,
                  ),
                  const SizedBox(height: 19),
                  ProfileSurface(
                    color: OnboardingTheme.soft,
                    radius: 16,
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        ProfileAvatar(
                          name: widget.expert,
                          size: 35,
                          expert: true,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.expert ?? 'Diyetisyenin',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'İzinlerin bu bağlantı için geçerli.',
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.5,
                                  color: OnboardingTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Paylaşım izinleri yükleniyor',
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: OnboardingTheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (_ready) ...[
                    for (final key in _sharingCopy.keys) _permissionRow(key),
                    const SizedBox(height: 17),
                    const Text(
                      'Her kategori ayrı yönetilir. Bir paylaşımı kapatmak diğer izinlerini ve kendi kayıtlarını değiştirmez.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.65,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_saving)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Paylaşım tercihlerin kaydediliyor',
                      ),
                    FilledButton(
                      onPressed: _saving || _changes.isEmpty ? null : _save,
                      style: profilePrimaryStyle(),
                      child: Text(
                        _saving ? 'Kaydediliyor…' : 'Tercihlerimi kaydet',
                      ),
                    ),
                  ] else if (!_loading)
                    TextButton(
                      onPressed: _saving ? null : _load,
                      child: const Text('İzinleri yeniden yükle'),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _finish(ProfileSharingResult.connections),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('Bağlantılarımı gör'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _finish(ProfileSharingResult.findExpert),
                    child: const Text(
                      'Diyetisyen Bul',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _permissionRow(String key) {
    final water = key == 'water_logs',
        granted = _granted(_permissions, key),
        value = _draft[key] ?? false;
    final label = _sharingCopy[key]!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      constraints: const BoxConstraints(minHeight: 65),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OnboardingTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label.$1,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    if (water)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: OnboardingTheme.soft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          granted
                              ? (value ? 'Paylaşım açık' : 'Kapatılacak')
                              : 'Yalnız bende',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3D7756),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  water && granted
                      ? 'Mevcut su paylaşım iznini geri alabilirsin.'
                      : label.$2,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: OnboardingTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Semantics(
            label: '${label.$1} paylaşımı',
            child: Switch(
              key: ValueKey('sharing-$key'),
              value: value,
              onChanged: _saving || (water && !granted)
                  ? null
                  : (v) => _change(key, v),
              activeThumbColor: OnboardingTheme.lime,
              activeTrackColor: OnboardingTheme.ink,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFE3EBDB),
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              trackOutlineWidth: const WidgetStatePropertyAll(0),
            ),
          ),
        ],
      ),
    );
  }
}
