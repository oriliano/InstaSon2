import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String chatId;
  final List<String> participants;
  final DateTime lastMessageTime;
  final String lastMessage;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final bool isGroup;
  final String? groupName;
  final String? groupImageUrl;

  ChatModel({
    required this.chatId,
    required this.participants,
    required this.lastMessageTime,
    required this.lastMessage,
    required this.lastMessageSenderId,
    required this.unreadCount,
    this.isGroup = false,
    this.groupName,
    this.groupImageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'participants': participants,
      'lastMessageTime': lastMessageTime,
      'lastMessage': lastMessage,
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      'isGroup': isGroup,
      'groupName': groupName,
      'groupImageUrl': groupImageUrl,
    };
  }

  factory ChatModel.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;

    Map<String, int> unreadCountMap = {};
    if (data['unreadCount'] != null) {
      final unreadData = data['unreadCount'] as Map<String, dynamic>;
      unreadData.forEach((key, value) {
        unreadCountMap[key] = value as int;
      });
    }

    DateTime lastMessageTime;
    if (data['lastMessageTime'] != null) {
      lastMessageTime = (data['lastMessageTime'] as Timestamp).toDate();
    } else {
      lastMessageTime = DateTime.now();
    }

    return ChatModel(
      chatId: snapshot.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessageTime: lastMessageTime,
      lastMessage: data['lastMessage'] ?? '',
      lastMessageSenderId: data['lastMessageSenderId'] ?? '',
      unreadCount: unreadCountMap,
      isGroup: data['isGroup'] ?? false,
      groupName: data['groupName'],
      groupImageUrl: data['groupImageUrl'],
    );
  }
}
