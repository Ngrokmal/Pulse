import 'package:flutter/foundation.dart';

class PerformanceMonitor {
  PerformanceMonitor._privateConstructor();
  static final PerformanceMonitor instance = PerformanceMonitor._privateConstructor();

  /// চ্যাট বা গ্রুপ মেসেজিং কোয়েরির লেটেন্সি এবং কস্ট ট্র্যাক করার জন্য কাস্টম ট্রেস।
  /// বাগ ৯ এবং প্রোডাকশন গাইডের আর্কিটেকচারাল লোড ফিল্টারিং মনিটর করে।
  Future<T> traceNetworkExecution<T>({
    required String traceName,
    required Future<T> Function() execution,
  }) async {
    if (kReleaseMode) {
      // রিলিজ মোডে কাস্টম টেলিমেট্রি স্টার্ট মেকানিজম (Firebase Performance APM API Mocked)
      final stopwatch = Stopwatch()..start();
      try {
        final result = await execution();
        stopwatch.stop();
        debugPrint("APM TRACE: [$traceName] Success in ${stopwatch.elapsedMilliseconds}ms");
        return result;
      } catch (e) {
        stopwatch.stop();
        debugPrint("APM TRACE FAILURE: [$traceName] Fault detected after ${stopwatch.elapsedMilliseconds}ms");
        rethrow;
      }
    } else {
      return await execution();
    }
  }
}
