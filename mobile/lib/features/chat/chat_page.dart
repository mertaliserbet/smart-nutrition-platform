import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/onboarding_theme.dart';
import 'chat_sheets.dart';
import 'chat_view.dart';

/// Presentation only until direct messaging has an approved server contract.
/// The existing relationship API supplies identity, never a fabricated thread.
class ChatPage extends StatefulWidget {
  const ChatPage({
    this.active = true,
    this.refreshRevision = 0,
    this.api,
    this.onViewProfile,
    super.key,
  });
  final bool active;
  final int refreshRevision;
  final DietitianApi? api;
  final VoidCallback? onViewProfile;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  AuthSession? _session;
  DietitianApi? _api;
  String? _owner, _error, _expert;
  RelationshipResponse? _relationship;
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _loading = false, _loaded = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  int _revision = 0;
  bool get _authorized =>
      widget.active &&
      _foreground &&
      _session?.isAuthenticated == true &&
      _owner != null &&
      _owner == _session?.user?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _bindApi() {
    final session = _session;
    _api = session == null
        ? null
        : identical(widget.api?.session, session)
        ? widget.api
        : DietitianApi(session);
  }

  void _clear() {
    ++_revision;
    _relationship = null;
    _expert = null;
    _error = null;
    _loading = false;
    _loaded = false;
    _draft.clear();
    _focus.unfocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || session?.user?.id != _owner) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _bindApi();
    }
    if (!_authorized) _clear();
    if (_authorized && !_loaded && !_loading && _error == null) _load();
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.api != widget.api) {
      _clear();
      _bindApi();
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

  Future<void> _load() async {
    if (!_authorized || _api == null || _loading) return;
    final revision = ++_revision, api = _api!;
    bool current() => mounted && _authorized && revision == _revision;
    setState(() {
      _relationship = null;
      _expert = null;
      _error = null;
      _loading = true;
      _loaded = false;
    });
    try {
      final active = await api.relationships(status: 'active');
      if (!current()) return;
      if (active.totalCount > 1 ||
          active.items.length != active.totalCount ||
          active.items.any((r) => r.status != 'active')) {
        throw const DietitianApiException.invalidResponse();
      }
      final relationship = active.items.isEmpty ? null : active.items.single;
      setState(() {
        _relationship = relationship;
        _loaded = true;
      });
      if (relationship != null) {
        _resolveName(api, relationship.dietitianId, revision);
      }
    } catch (error) {
      if (current()) {
        setState(
          () => _error = error is DietitianApiException
              ? error.message
              : 'Diyetisyen bağlantın yüklenemedi. Lütfen yeniden dene.',
        );
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _resolveName(DietitianApi api, String id, int revision) async {
    bool current() => mounted && _authorized && revision == _revision;
    try {
      var page = 1, seen = 0;
      while (current()) {
        final result = await api.search(page: page);
        if (!current()) return;
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
      /* The verified relationship remains usable without a directory name. */
    }
  }

  Future<void> _reload() async {
    setState(_clear);
    await _load();
  }

  Future<void> _connect() async {
    if (!_authorized) return;
    final owner = _owner;
    await Navigator.of(context).pushNamed('/dietitians');
    if (mounted && _authorized && owner == _owner) await _reload();
  }

  void _prompt(String value) {
    if (!_authorized || _relationship == null) return;
    _draft.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focus.requestFocus();
  }

  Future<void> _sheet({required bool attachment}) async {
    if (!_authorized || _relationship == null) return;
    _focus.unfocus();
    final owner = _owner, session = _session!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OnboardingTheme.background,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ChatSheet(
        attachment: attachment,
        expert: _expert,
        session: session,
        owner: owner,
      ),
    );
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: ChatView(
      name: _authorized ? _session?.user?.displayName : null,
      expert: _authorized ? _expert : null,
      authorized: _authorized,
      loading: _loading,
      loaded: _loaded,
      connected: _relationship != null,
      error: _error,
      draft: _draft,
      focus: _focus,
      scroll: _scroll,
      onRetry: _reload,
      onConnect: _connect,
      onPrompt: _prompt,
      onProfile: widget.onViewProfile,
      onInfo: () => _sheet(attachment: false),
      onAttach: () => _sheet(attachment: true),
    ),
  );
}
