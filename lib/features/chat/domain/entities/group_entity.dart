class GroupEntity {
  final String groupId;
  final String name;
  final String creatorId;
  final List<String> cachedMemberUids; // রুল ৮ ও বাগ ৯: ওয়ান-শট ক্যাশ রিড ফর সিকিউরিটি
  final List<String> adminIds; // Milestone 5: admin role list, createGroup-এ creator প্রথম admin হিসেবে যোগ হয়
  final DateTime createdAt;
  // Milestone 6: Cloudinary-hosted group photo। দুটোই nullable এবং optional —
  // পুরনো group document-এ এই ফিল্ড দুটো না-ও থাকতে পারে (createGroup এখনো এগুলো
  // লেখে না), এবং কোনো group কখনো ছবি সেট না-ও করতে পারে। groupPhotoPublicId
  // Firestore schema-তে persist করা হয় শুধুমাত্র replace-এর সময় পুরনো Cloudinary
  // asset ডিলিট করার জন্য — Cloudinary folder naming Firestore collection
  // naming থেকে সম্পূর্ণ স্বতন্ত্র (কোনো `chats/...` পাথ mirror করা হয় না)।
  final String? groupPhotoUrl;
  final String? groupPhotoPublicId;

  const GroupEntity({
    required this.groupId,
    required this.name,
    required this.creatorId,
    required this.cachedMemberUids,
    required this.adminIds,
    required this.createdAt,
    this.groupPhotoUrl,
    this.groupPhotoPublicId,
  });

  /// Milestone 5: permission check — adminIds-এ থাকলে অথবা creator হলে true।
  /// creator সবসময় implicit admin (backward-compat: পুরনো group document-এ
  /// adminIds না-ও থাকতে পারে, তখন খালি লিস্ট আসে — creator permission ভাঙে না)।
  bool isAdmin(String uid) => adminIds.contains(uid) || uid == creatorId;
}
