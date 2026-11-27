import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../body_measurements/body_measurement_api.dart';
import '../body_measurements/measurement_overview.dart';
import '../body_measurements/body_measurement_detail_page.dart';
import '../body_measurements/body_measurement_form_page.dart';
import '../onboarding/onboarding_theme.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({
    this.api,
    this.active = true,
    this.onViewProfile,
    this.refreshRevision = 0,
    this.now = DateTime.now,
    super.key,
  });
  final bool active;
  final BodyMeasurementApi? api;
  final VoidCallback? onViewProfile;
  final int refreshRevision;
  final DateTime Function() now;
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  BodyMeasurementApi? _api;
  String? _owner, _error;
  List<BodyMeasurement>? _data;
  int _generation = 0;
  bool _loading = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _authorized =>
      widget.active &&
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
      _resolveApi();
    }
    if (!_authorized) {
      _clear();
    } else if (_data == null && !_loading && _error == null) {
      _load();
    }
  }

  void _resolveApi() {
    _api = widget.api != null && identical(widget.api!.session, _session)
        ? widget.api
        : (_session == null ? null : BodyMeasurementApi(_session!));
  }

  @override
  void didUpdateWidget(covariant ProgressPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active ||
        old.api != widget.api ||
        old.refreshRevision != widget.refreshRevision) {
      _clear();
      _resolveApi();
      if (_authorized) _load();
    }
  }

  void _clear() {
    ++_generation;
    _data = null;
    _error = null;
    _loading = false;
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
    if (!_authorized || _api == null || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      final rows = await _api!.history();
      if (mounted && _authorized && generation == _generation) {
        setState(() => _data = rows);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is BodyMeasurementApiException
              ? error.message
              : 'Ölçümler yüklenemedi.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _add() async {
    if (!_authorized || _api == null) return;
    final owner = _owner;
    final saved = await showBodyMeasurementForm(context, api: _api!);
    await _afterOpen(saved, owner);
  }

  Future<void> _detail(BodyMeasurement row) async {
    if (!_authorized || _api == null) return;
    final owner = _owner;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: OnboardingTheme.data,
          child: BodyMeasurementDetailPage(id: row.id, api: _api),
        ),
      ),
    );
    await _afterOpen(saved, owner);
  }

  Future<void> _afterOpen(bool? saved, String? owner) async {
    if (!mounted || !_authorized || owner != _owner) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ölçüm işlemi tamamlandı.')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: ColoredBox(
      color: OnboardingTheme.background,
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          key: ValueKey('measurement-scroll-$_owner'),
          physics: const AlwaysScrollableScrollPhysics(),
          child: MeasurementOverview(
            key: ValueKey(_owner),
            rows: _authorized ? (_data ?? []) : [],
            now: widget.now(),
            authorized: _authorized,
            loading: _loading,
            error: _error,
            name: _authorized ? _session?.user?.displayName : null,
            onAdd: _add,
            onRetry: _load,
            onOpen: _detail,
            onProfile: widget.onViewProfile,
          ),
        ),
      ),
    ),
  );
}
