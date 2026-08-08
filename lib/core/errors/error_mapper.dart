import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'exceptions.dart';
import 'failures.dart';

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
  return 'কিছু একটা সমস্যা হয়েছে। আবার চেষ্টা করুন।';
}
