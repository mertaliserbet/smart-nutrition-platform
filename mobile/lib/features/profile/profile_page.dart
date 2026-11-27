import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../auth/web_panel_link.dart';
import '../dietitians/dietitian_account_page.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/onboarding_theme.dart';
import 'profile_overview.dart';
import 'profile_sheets.dart';
import 'profile_sharing_sheet.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    this.active = true,
    this.refreshRevision = 0,
    this.api,
    this.onLogout,
    super.key,
  });
  final bool active;
  final int refreshRevision;
  final DietitianApi? api;
  final Future<void> Function()? onLogout;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  AuthSession? _session;
  DietitianApi? _api;
  String? _owner, _expert, _connectionError, _professionalError;
  RelationshipResponse? _relationship;
  DietitianStatusResponse? _professional;
  bool _loadingConnection = false,
      _connectionLoaded = false,
      _loadingProfessional = false,
      _professionalLoaded = false,
      _loggingOut = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  int _revision = 0;
  bool get _authorized =>
      widget.active &&
      _foreground &&
      _owner != null &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  bool _current(int revision) =>
      mounted && _authorized && revision == _revision;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    ++_revision;
    _expert = null;
    _relationship = null;
    _professional = null;
    _connectionError = null;
    _professionalError = null;
    _loadingConnection = false;
    _loadingProfessional = false;
    _connectionLoaded = false;
    _professionalLoaded = false;
  }

  void _bind() {
    final session = _session;
    _api = session == null
        ? null
        : identical(widget.api?.session, session)
        ? widget.api
        : DietitianApi(session);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || session?.user?.id != _owner) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _bind();
    }
    if (!_authorized) _clear();
    if (_authorized &&
        !_connectionLoaded &&
        !_loadingConnection &&
        _connectionError == null &&
        !_loadingProfessional &&
        !_professionalLoaded &&
        _professionalError == null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.refreshRevision != oldWidget.refreshRevision ||
        widget.api != oldWidget.api) {
      _clear();
      _bind();
      if (_authorized) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _clear();
    });
    if (_authorized) _load();
  }

  Future<void> _reload() async {
    setState(_clear);
    await _load();
  }

  Future<void> _load() async {
    if (!_authorized || _api == null) return;
    final revision = ++_revision;
    setState(() {
      _loadingConnection = true;
      _loadingProfessional = true;
    });
    await Future.wait([_loadConnection(revision), _loadProfessional(revision)]);
  }

  Future<void> _loadConnection(int revision) async {
    try {
      final rows = await _api!.relationships(status: 'active');
      if (!_current(revision)) return;
      if (rows.totalCount > 1 ||
          rows.items.length != rows.totalCount ||
          rows.items.any((r) => r.status != 'active')) {
        throw const DietitianApiException.invalidResponse();
      }
      setState(() {
        _relationship = rows.items.firstOrNull;
        _connectionLoaded = true;
      });
      if (_relationship != null) {
        _resolveName(_api!, _relationship!.dietitianId, revision);
      }
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _connectionError = error is DietitianApiException
              ? error.message
              : 'Diyetisyen bağlantın yüklenemedi.',
        );
      }
    } finally {
      if (_current(revision)) setState(() => _loadingConnection = false);
    }
  }

  Future<void> _resolveName(DietitianApi api, String id, int revision) async {
    try {
      var page = 1, seen = 0;
      while (_current(revision)) {
        final result = await api.search(page: page);
        if (!_current(revision)) return;
        for (final expert in result.items) {
          if (expert.id == id) {
            setState(() => _expert = expert.displayName);
            return;
          }
        }
        seen += result.items.length;
        if (result.items.isEmpty || seen >= result.totalCount) return;
        page++;
      }
    } catch (_) {
      /* A missing directory name must not hide a verified relationship. */
    }
  }

  Future<void> _loadProfessional(int revision) async {
    try {
      final profile = await _api!.profile();
      if (_current(revision)) {
        setState(() {
          _professional = profile;
          _professionalLoaded = true;
        });
      }
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _professionalError = error is DietitianApiException
              ? error.message
              : 'Diyetisyen başvuru durumun yüklenemedi.',
        );
      }
    } finally {
      if (_current(revision)) setState(() => _loadingProfessional = false);
    }
  }

  Future<void> _route(String path) async {
    if (!_authorized) return;
    final owner = _owner;
    await Navigator.of(context).pushNamed(path);
    if (mounted && _authorized && owner == _owner) await _reload();
  }

  Future<void> _sharing() async {
    if (!_authorized) return;
    if (_relationship == null || _api == null) {
      await _route('/client-connections');
      return;
    }
    final owner = _owner!,
        session = _session!,
        api = _api!,
        relationshipId = _relationship!.id,
        expert = _expert;
    final result = await showModalBottomSheet<ProfileSharingResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: OnboardingTheme.background,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ProfileSharingSheet(
        api: api,
        session: session,
        owner: owner,
        relationshipId: relationshipId,
        expert: expert,
      ),
    );
    if (!mounted || !_authorized || owner != _owner) return;
    if (result == ProfileSharingResult.connections) {
      await _route('/client-connections');
    } else if (result == ProfileSharingResult.findExpert) {
      await _route('/dietitians');
    } else if (result == ProfileSharingResult.saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşım tercihlerin kaydedildi.')),
      );
      await _reload();
    }
  }

  Future<void> _sheet(ProfileSheetKind kind) async {
    if (!_authorized) return;
    final owner = _owner!, session = _session!, revision = _revision;
    final action = await showModalBottomSheet<ProfileAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OnboardingTheme.background,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ProfileSheet(
        kind: kind,
        session: session,
        owner: owner,
        user: session.user!,
        professional: _professional,
        professionalKnown: _professionalLoaded && _professionalError == null,
      ),
    );
    if (!mounted || !_current(revision) || action == null) return;
    switch (action) {
      case ProfileAction.refresh:
        await _reload();
      case ProfileAction.resetPassword:
        await _route('/forgot-password');
      case ProfileAction.applyExpert:
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ProfileRouteGuard(
              session: session,
              owner: owner,
              child: Theme(
                data: OnboardingTheme.data,
                child: const DietitianAccountPage(),
              ),
            ),
          ),
        );
        if (mounted && _authorized && owner == _owner) await _reload();
      case ProfileAction.expertWeb:
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ProfileRouteGuard(
              session: session,
              owner: owner,
              child: const WebPanelPage(),
            ),
          ),
        );
      case ProfileAction.signOut:
        if (_loggingOut) return;
        setState(() => _loggingOut = true);
        try {
          await (widget.onLogout?.call() ?? session.signOut());
        } catch (_) {
          if (mounted && _authorized) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Çıkış işlemi tamamlanamadı. Yeniden dene.'),
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _loggingOut = false);
        }
    }
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: RefreshIndicator(
      onRefresh: _reload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ProfileOverview(
          user: _authorized ? _session?.user : null,
          authorized: _authorized,
          expert: _expert,
          connected: _relationship != null,
          loadingConnection: _loadingConnection,
          connectionLoaded: _connectionLoaded,
          connectionError: _connectionError,
          professional: _professional,
          loadingProfessional: _loadingProfessional,
          professionalKnown: _professionalLoaded,
          professionalError: _professionalError,
          loggingOut: _loggingOut,
          onRetry: _reload,
          onFind: () => _route('/dietitians'),
          onConnections: () => _route('/client-connections'),
          onSharing: _sharing,
          onSheet: _sheet,
          onRoute: _route,
        ),
      ),
    ),
  );
}
