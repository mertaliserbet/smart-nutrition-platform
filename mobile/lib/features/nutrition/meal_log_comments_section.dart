import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import 'meal_log_comment_api.dart';

class MealLogCommentsSection extends StatefulWidget {
  const MealLogCommentsSection({
    required this.mealLogId,
    this.api,
    this.onUnavailable,
    super.key,
  });
  final String mealLogId;
  final MealLogCommentApi? api;
  final ValueChanged<MealLogCommentApiException>? onUnavailable;
  @override
  State<MealLogCommentsSection> createState() => _MealLogCommentsSectionState();
}

class _MealLogCommentsSectionState extends State<MealLogCommentsSection>
    with WidgetsBindingObserver {
  AuthSession? _session;
  MealLogCommentApi? _api;
  String? _owner, _error, _sendError, _notice;
  List<MealLogComment> _rows = [];
  MealLogComment? _parent;
  final _draft = TextEditingController();
  int _generation = 0, _page = 1, _total = 0;
  bool _loading = false,
      _loaded = false,
      _verified = false,
      _sending = false,
      _uncertain = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _owner == _session?.user?.id;
  bool get _canReply =>
      _authorized && _verified && !_loading && !_sending && !_uncertain;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    ++_generation;
    _rows = [];
    _parent = null;
    _draft.clear();
    _total = 0;
    _page = 1;
    _error = null;
    _sendError = null;
    _notice = null;
    _loading = false;
    _loaded = false;
    _verified = false;
    _uncertain = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _api = session == null
          ? null
          : identical(widget.api?.session, session)
          ? widget.api
          : MealLogCommentApi(session);
    }
    if (!_authorized) {
      _clear();
    } else if (!_loaded && !_loading) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant MealLogCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mealLogId != widget.mealLogId ||
        oldWidget.api != widget.api) {
      _clear();
      _api = _session == null
          ? null
          : identical(widget.api?.session, _session)
          ? widget.api
          : MealLogCommentApi(_session!);
      if (_authorized) {
        _load();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _clear();
    });
    if (_authorized) {
      _load();
    }
  }

  Future<void> _load({int page = 1}) async {
    if (!_authorized || _api == null) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _verified = false;
      _rows = [];
      _parent = null;
      _draft.clear();
      _error = null;
      _sendError = null;
    });
    try {
      final result = await _api!.list(widget.mealLogId, page: page);
      if (!mounted || !_authorized || generation != _generation) {
        return;
      }
      setState(() {
        _rows = result.items;
        _total = result.totalCount;
        _page = page;
        _verified = true;
        _uncertain = false;
      });
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        final failure = error is MealLogCommentApiException
            ? error
            : const MealLogCommentApiException(
                'Yorumlar yüklenemedi. Yeniden deneyin.',
              );
        setState(() {
          _error = failure.message;
          _notice = null;
        });
        if ([401, 403, 404].contains(failure.statusCode)) {
          widget.onUnavailable?.call(failure);
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _reply() async {
    var refreshed = false;
    final parent = _parent;
    if (!_canReply || parent == null) {
      return;
    }
    if (!MealLogCommentApi.validText(_draft.text)) {
      setState(
        () => _sendError =
            'Yanıt 1–2000 karakter olmalı; yalnız boşluk içeremez.',
      );
      return;
    }
    final generation = ++_generation;
    setState(() {
      _sending = true;
      _sendError = null;
      _notice = null;
    });
    try {
      await _api!.reply(widget.mealLogId, parent, _draft.text);
      if (!mounted || !_authorized || generation != _generation) {
        return;
      }
      setState(() {
        _notice = 'Yanıtınız kaydedildi.';
        _draft.clear();
        _parent = null;
      });
      refreshed = true;
      await _load(page: ((_total + 1) / 10).ceil());
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        final failure = error is MealLogCommentApiException
            ? error
            : const MealLogCommentApiException(
                'Gönderim sonucu doğrulanamadı. Yorumları yenileyip kontrol edin.',
                uncertain: true,
              );
        setState(() {
          _sendError = failure.message;
          _uncertain = failure.uncertain;
        });
        if ([401, 403, 404].contains(failure.statusCode)) {
          setState(() {
            _rows = [];
            _draft.clear();
            _parent = null;
            _verified = false;
          });
          widget.onUnavailable?.call(failure);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        // A background/account change discarded the outcome; only re-read, never replay POST.
        if (_authorized && generation != _generation && !refreshed) {
          await _load(page: _page);
        }
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _draft.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.day}.${local.month}.${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _draft,
        enabled: _canReply,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Yanıtınız',
          helperText: '1–2000 karakter',
        ),
        onChanged: (_) => setState(() => _sendError = null),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _canReply ? _reply : null,
        child: const Text('Yanıt gönder'),
      ),
      TextButton(
        onPressed: _canReply
            ? () => setState(() {
                _parent = null;
                _draft.clear();
                _sendError = null;
              })
            : null,
        child: const Text('Yanıttan vazgeç'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Diyetisyen yorumları ve yanıtlar',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_loading)
          const LinearProgressIndicator(semanticsLabel: 'Yorumlar yükleniyor'),
        if (_sending)
          const LinearProgressIndicator(semanticsLabel: 'Yanıt gönderiliyor'),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_sendError != null)
          Semantics(liveRegion: true, child: Text(_sendError!)),
        if (_uncertain)
          const Text(
            'Yanıtı yeniden göndermeden önce yorumları yenileyip sonucu kontrol edin.',
          ),
        if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
        if (_verified && !_loading) ...[
          if (_rows.isEmpty)
            Text(
              _total == 0
                  ? 'Henüz yorum veya yanıt yok.'
                  : 'Bu sayfada yorum kalmadı. Önceki sayfaya dönebilirsiniz.',
            ),
          for (final row in _rows)
            Card(
              child: Padding(
                padding: EdgeInsets.fromLTRB(row.isRoot ? 16 : 28, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row.isRoot ? 'Diyetisyen yorumu' : 'Danışan yanıtı',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(_time(row.createdAt)),
                    if (!row.isRoot)
                      Text(
                        _rows
                                .where(
                                  (root) =>
                                      root.id == row.parentCommentId &&
                                      root.isRoot,
                                )
                                .firstOrNull
                                ?.text ??
                            'İlgili yorum başka bir sayfada.',
                      ),
                    Text(row.text),
                    if (row.isRoot && _parent?.id != row.id)
                      TextButton(
                        key: ValueKey('reply-${row.id}'),
                        onPressed: _canReply
                            ? () => setState(() {
                                _parent = row;
                                _draft.clear();
                                _sendError = null;
                                _notice = null;
                              })
                            : null,
                        child: const Text('Yanıtla'),
                      ),
                    if (row.isRoot && _parent?.id == row.id) _editor(),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: !_sending && _page > 1
                    ? () => _load(page: _page - 1)
                    : null,
                child: const Text('Önceki yorum sayfası'),
              ),
              Text('$_total yorum/yanıt · Sayfa $_page'),
              OutlinedButton(
                onPressed: !_sending && _page * 10 < _total
                    ? () => _load(page: _page + 1)
                    : null,
                child: const Text('Sonraki yorum sayfası'),
              ),
            ],
          ),
        ],
        TextButton.icon(
          onPressed: _loading || _sending ? null : () => _load(page: _page),
          icon: const Icon(Icons.refresh),
          label: const Text('Yorumları yenile'),
        ),
      ],
    );
  }
}
