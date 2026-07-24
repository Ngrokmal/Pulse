import 'package:flutter/material.dart';

class MediaCacheManager {
  MediaCacheManager._privateConstructor();
  static final MediaCacheManager instance = MediaCacheManager._privateConstructor();

  /// বাগ ৮ ফিক্স: চ্যাট স্ক্রিন স্ক্রোল বা লিভ করার সময় ফ্লাটার ইঞ্জিনের 
  /// ImageCache জ্যাম হওয়া থেকে বাঁচানো এবং ওওএম ক্র্যাশ প্রতিরোধ করা।
  void forceFlushImageMemory() {
    try {
      final ImageCache imageCache = PaintingBinding.instance.imageCache;
      
      // লাইভ ইমেজ এবং পেন্ডিং ক্যাশ মেমোরি থেকে সম্পূর্ণ রিলিজ করা
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      // সিস্টেম ফেইলর বা বাইন্ডিং এক্সেপশন ফলব্যাক ট্র্যাপ (রুল ৫)
      debugPrint("MediaCacheManager Error: ${e.toString()}");
    }
  }
}
