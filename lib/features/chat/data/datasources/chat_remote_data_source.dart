import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../../../core/errors/exceptions.dart';

abstract class ChatRemoteDataSource {
  Future<void> sendMessage({required String chatId, required Map<String, dynamic> messageData});
}

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final FirebaseFirestore _firestore;

  ChatRemoteDataSourceImpl({required FirebaseFirestore firestore}) : _firestore = firestore;

  @override
  Future<void> sendMessage({required String chatId, required Map<String, dynamic> messageData}) async {
    try {
      final String messageId = messageData['messageId'] as String;
      
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .set(messageData);
    } on FirebaseAuthException catch (e) {
      throw ServerException(message: e.message ?? "Authentication Failed");
    } on FirebaseException catch (e) {
      throw ServerException(message: e.message ?? "Firestore Error");
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? "Connection Timeout");
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? "Platform Error");
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }
}
