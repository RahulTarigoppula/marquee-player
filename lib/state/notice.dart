// One-line notices ("That file has moved.", "Removed from the library · Undo"). Any screen
// shows one with `ref.read(noticeProvider.notifier).show(...)`; the app shell renders the
// current notice above every room and clears it after [Notice.duration].
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class Notice {
  final String text;

  /// Optional action shown beside the text, e.g. "Undo".
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  /// Distinguishes two notices with the same text (so the shell restarts its timer).
  final int serial;

  const Notice(
    this.text, {
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
    this.serial = 0,
  });
}

class NoticeNotifier extends Notifier<Notice?> {
  int _serial = 0;

  @override
  Notice? build() => null;

  void show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) => state = Notice(
    text,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
    serial: ++_serial,
  );

  /// Clears [notice] if it is still the one showing.
  void dismiss([Notice? notice]) {
    if (notice == null || identical(state, notice)) state = null;
  }
}

final noticeProvider = NotifierProvider<NoticeNotifier, Notice?>(NoticeNotifier.new);
