import 'dart:async';
import 'dart:io';
import 'dart:math';

/// একটি কিউ করা টাস্ক + তার caller-facing completer। Stability fix (ধারা
/// দেখুন নিচে addToQueue-এ): আগে `addToQueue` `void` রিটার্ন করত এবং
/// non-SocketException এরর হলে `success = true` সেট করে টাস্ক silently ড্রপ
/// করা হতো — caller কখনো জানতেই পারত না যে তার write/mark-as-read/send
/// আসলে ব্যর্থ হয়েছে। এখন প্রতিটি টাস্কের একটি Completer থাকে, যার
/// Future `addToQueue` রিটার্ন করে — caller ইচ্ছা করলে await/try-catch করতে
/// পারে (fire-and-forget call site-গুলো আগের মতোই কাজ করবে, কারণ `void` থেকে
/// `Future<void>`-এ রিটার্ন টাইপ পরিবর্তন Dart-এ non-breaking — আগে কেউ রিটার্ন
/// ভ্যালু ব্যবহার করত না)।
class _QueuedTask {
  final Future<void> Function() run;
  final Completer<void> completer;
  _QueuedTask(this.run, this.completer);
}

class OfflineQueueManager {
  OfflineQueueManager._privateConstructor();
  static final OfflineQueueManager instance = OfflineQueueManager._privateConstructor();

  final List<_QueuedTask> _queue = [];
  bool _isProcessing = false;

  /// Phase 8.5H (Firestore Security Rules Foundation).
  ///
  /// Every queued task here is a closure that was captured while a
  /// specific user was signed in (it writes to that user's uid-scoped
  /// document paths). This queue is a process-wide singleton, so a task
  /// queued right before sign-out (e.g. stuck in SocketException backoff)
  /// can still be sitting here after a *different* user signs in.
  ///
  /// That replay is not a data-corruption risk under ownership-based
  /// rules (`request.auth.uid == uid`) — Firestore will reject the write
  /// because the new session's auth.uid won't match the path baked into
  /// the closure. But today that shows up to the new user as a mysterious
  /// permission-denied error for an action they didn't take. Call this
  /// from the sign-out path so pending tasks are dropped (and their
  /// callers' Futures resolve) instead of silently carrying over into
  /// the next session.
  void clear() {
    if (_queue.isEmpty) return;
    final pending = List<_QueuedTask>.from(_queue);
    _queue.clear();
    for (final task in pending) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(
          StateError('OfflineQueueManager: task cancelled (user signed out)'),
        );
      }
    }
  }

  /// রিটার্ন টাইপ `void` থেকে `Future<void>`-এ পরিবর্তন হয়েছে (non-breaking,
  /// উপরে comment দেখুন)। এই Future সম্পূর্ণ হয় যখন এই নির্দিষ্ট টাস্কটি
  /// সফল হয়, অথবা একটি non-network (genuine/permanent) এরর হলে reject হয়ে
  /// (caller await করলে ধরতে পারবে — silent failure আর নেই)। SocketException
  /// দিয়ে ৫ বার রিট্রাই শেষ হয়ে গেলেও টাস্কটি queue-তে *থেকে যায়* (আগের
  /// ইচ্ছাকৃত অফলাইন-রেজিলিয়েন্স আচরণ অপরিবর্তিত — নেটওয়ার্ক ফিরে এলে পরের
  /// addToQueue কল আবার প্রসেস ট্রিগার করবে) — তাই স্থায়ী নেটওয়ার্ক-ডাউন
  /// অবস্থায় এই Future অনির্দিষ্টকালের জন্য pending থাকতে পারে; UI-facing
  /// caller-দের (Bloc লেয়ার) তাই নিজ নিজ `.timeout()` প্রয়োগ করা উচিত
  /// (এই মাইলস্টোনের ChatBloc/GroupChatBloc/GroupInfoBloc/GroupBloc-এ করা
  /// হয়েছে) — "Prevent infinite loading" রিকোয়ারমেন্ট।
  Future<void> addToQueue(Future<void> Function() task) {
    final completer = Completer<void>();
    _queue.add(_QueuedTask(task, completer));
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final queuedTask = _queue.first;
      int retryCount = 0;
      bool success = false;
      Object? lastError;

      while (!success && retryCount < 5) {
        try {
          await queuedTask.run();
          success = true;
        } on SocketException catch (e) {
          lastError = e;
          retryCount++;
          // Exponential Backoff: 2^retryCount + jitter
          final int backoffSeconds = pow(2, retryCount).toInt() + Random().nextInt(2);
          await Future.delayed(Duration(seconds: backoffSeconds));
        } catch (e) {
          // Stability fix: গুরুতর অন্য কোনো (non-network) এরর হলে আর
          // silently "success" ধরা হয় না — queue ব্লক না করতে টাস্কটি
          // নিচে queue থেকে সরানো হয়, কিন্তু caller-এর Future এখন error
          // দিয়ে complete হয় (silent failure fix)।
          lastError = e;
          break;
        }
      }

      if (success) {
        _queue.removeAt(0);
        queuedTask.completer.complete();
      } else if (retryCount >= 5) {
        // SocketException-এ ৫ বার রিট্রাই শেষ — নেটওয়ার্ক স্থায়ীভাবে ডাউন
        // থাকতে পারে বলে ধরে নিয়ে টাস্কটি queue-তে *রেখে* লুপ ব্রেক করা হয়
        // (আগের আচরণ অপরিবর্তিত — পরবর্তী addToQueue কল আবার ট্রাই করবে)।
        break;
      } else {
        // non-network permanent error — টাস্ক ড্রপ, caller error পায়, বাকি
        // queue চলতে থাকে (silent-drop এর বদলে reported failure)।
        _queue.removeAt(0);
        queuedTask.completer.completeError(
          lastError ?? StateError('OfflineQueueManager: task failed'),
        );
      }
    }
    _isProcessing = false;
  }
}
