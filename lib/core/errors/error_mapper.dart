import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'exceptions.dart';
import 'failures.dart';

/// Stability + Error Handling milestone: এখন পর্যন্ত প্রতিটি Bloc নিজের মতো
/// `error.toString()` সরাসরি ErrorState-এ পাঠাত (raw Dart exception টেক্সট,
/// যেমন `SocketException: Failed host lookup...` বা
/// `[cloud_firestore/unavailable] The service is currently unavailable.`) —
/// টেকনিক্যাল, ইউজার-ফ্রেন্ডলি নয়, এবং প্রতিটি Bloc-এ আলাদা আলাদা (ইনকনসিস্টেন্ট)।
///
/// এই একটি ফাংশন সব Bloc-এর onError/catch থেকে reuse হয় (ChatBloc,
/// GroupChatBloc, GroupInfoBloc, GroupBloc, ChatListBloc) — কোনো নতুন
/// exception টাইপ/collection/schema যোগ হয়নি, শুধু বিদ্যমান
/// exceptions.dart/failures.dart-এর টাইপগুলো একটি user-friendly বাক্যে ম্যাপ
/// করা হয়েছে। এটিই "Standardize ErrorState" + "user-friendly SnackBar/Dialog"
/// রিকোয়ারমেন্টের একমাত্র সোর্স অফ ট্রুথ।
String friendlyErrorMessage(Object error) {
  if (error is ModerationBlockedException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'সংযোগে সময় বেশি লাগছে। ইন্টারনেট চেক করে আবার চেষ্টা করুন।';
  }
  if (error is SocketException) {
    return 'ইন্টারনেট কানেকশন নেই। দয়া করে পুনরায় চেষ্টা করুন।';
  }
  if (error is NetworkException) {
    return error.message.isNotEmpty
        ? error.message
        : 'ইন্টারনেট কানেকশন নেই। দয়া করে পুনরায় চেষ্টা করুন।';
  }
  if (error is NetworkFailure) {
    return error.message;
  }
  if (error is ServerException) {
    return 'সার্ভারে সাময়িক সমস্যা হচ্ছে। কিছুক্ষণ পর আবার চেষ্টা করুন।';
  }
  if (error is FirebaseFailure) {
    return 'সার্ভারে সাময়িক সমস্যা হচ্ছে। কিছুক্ষণ পর আবার চেষ্টা করুন।';
  }
  if (error is CacheException) {
    return 'ডেটা লোড করতে সমস্যা হয়েছে। আবার চেষ্টা করুন।';
  }
  // ROOT CAUSE FIX (Home screen "কিছু একটা সমস্যা হয়েছে" after login):
  // ChatListRepositoryImpl.streamChatList/ChatRepositoryImpl.streamMessages
  // forward `.snapshots()` stream errors straight through via
  // `controller.addError(error)` — those are raw `FirebaseException`s from
  // the cloud_firestore SDK (e.g. `failed-precondition` when a composite
  // index a query needs hasn't been deployed yet, `permission-denied` from
  // firestore.rules, `unavailable` for a transient outage). None of those
  // were ever wrapped into this app's own exception types above, so every
  // single one of them — regardless of actual cause — fell through to the
  // generic fallback at the bottom of this function with zero diagnostic
  // signal, which is exactly the symptom reported. Distinguishing the
  // common codes here doesn't fix a missing index by itself (that's a
  // `firebase deploy --only firestore:indexes` step — see
  // firestore.indexes.json, which already declares the
  // participantIds+lastMessageAt composite index this screen's query
  // needs), but it turns an opaque, identical-looking failure into an
  // actionable one instead of erasing the code entirely.
  if (error is FirebaseException) {
    switch (error.code) {
      case 'failed-precondition':
        return 'সার্ভার কনফিগারেশন আপডেট হচ্ছে। কিছুক্ষণ পর আবার চেষ্টা করুন।';
      case 'permission-denied':
        return 'এই তথ্য দেখার অনুমতি নেই। আবার লগইন করে চেষ্টা করুন।';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'সার্ভারে সাময়িক সমস্যা হচ্ছে। কিছুক্ষণ পর আবার চেষ্টা করুন।';
      default:
        return 'কিছু একটা সমস্যা হয়েছে। আবার চেষ্টা করুন।';
    }
  }
  // অজানা/অন্যান্য এরর (UnknownException, StateError, generic Cloudinary
  // এরর) — silent হওয়া এড়াতে সবসময় একটি বোধগম্য fallback বাক্য, কোনো raw
  // stack/exception টেক্সট ইউজারকে দেখানো হয় না।
  return 'কিছু একটা সমস্যা হয়েছে। আবার চেষ্টা করুন।';
}
