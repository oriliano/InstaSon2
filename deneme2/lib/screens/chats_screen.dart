import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:instason/screens/create_group_message.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../models/chat_model.dart';
import 'chat_detail_screen.dart';
import 'new_chat_screen.dart';
import 'group_chat_detail_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({Key? key}) : super(key: key);
  @override
  State<ChatsScreen> createState() => ChatsScreenState();
}

class ChatsScreenState extends State<ChatsScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final userProfiles = <String, Map<String, dynamic>>{};
  bool isLoading = false;
  @override
  void initState() {
    super.initState();
  }

  Future<void> deleteChat(String chatId, bool isGroup) async {
    try {
// Önce sohbetteki tüm mesajları sil
      final messages = await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .where('chatId', isEqualTo: chatId)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (var message in messages.docs) {
        batch.delete(message.reference);
      }
// Sohbet belgesini sil
      batch.delete(FirebaseFirestore.instance
          .collection(AppConstants.chatsCollection)
          .doc(chatId));
// Eğer grupsa, grup belgesini de sil
      if (isGroup) {
        final chatDoc = await FirebaseFirestore.instance
            .collection(AppConstants.chatsCollection)
            .doc(chatId)
            .get();
        if (chatDoc.exists) {
          final chatData = chatDoc.data() as Map<String, dynamic>;
          final groupId = chatData['groupId'];
          if (groupId != null) {
            batch.delete(
                FirebaseFirestore.instance.collection('groups').doc(groupId));
          }
        }
      }
      await batch.commit();
// Başarı mesajı göster
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: isGroup ? 'Grup silindi' : 'Sohbet silindi',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      print('Sohbet silinirken hata: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Sohbet silinirken bir hata oluştu',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile(String userId) async {
// Profil bilgilerini zaten yüklediysen kullan
    if (userProfiles.containsKey(userId)) {
      return userProfiles[userId];
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        userProfiles[userId] = data;
        return data;
      }
    } catch (e) {
      print('Kullanıcı profili yüklenirken hata: $e');
    }
    return null;
  }

  String getReceiverName(Map<String, dynamic> chat) {
// Grup sohbeti kontrolü
    if (chat['isGroup'] == true) {
      return chat['groupName'] ?? 'Adsız Grup';
    }
    final participants = List<String>.from(chat['participants'] ?? []);
// Kendi ID'ni çıkar
    final otherParticipants =
        participants.where((id) => id != currentUserId).toList();
    if (otherParticipants.isEmpty) return 'Bilinmeyen Kullanıcı';
    final receiverId = otherParticipants.first;
    final receiverProfile = userProfiles[receiverId];
    return receiverProfile?['username'] ?? 'Yükleniyor...';
  }

  String getProfileImageUrl(Map<String, dynamic> chat) {
// Grup sohbeti kontrolü
    if (chat['isGroup'] == true) {
      return chat['groupImageUrl'] ?? '';
    }
    final participants = List<String>.from(chat['participants'] ?? []);
    final otherParticipants =
        participants.where((id) => id != currentUserId).toList();
    if (otherParticipants.isEmpty) return '';
    final receiverId = otherParticipants.first;
    final receiverProfile = userProfiles[receiverId];
    return receiverProfile?['profileImageUrl'] ?? '';
  }

  String formatLastMessage(Map<String, dynamic> chat) {
    final lastMessage = chat['lastMessage'] ?? '';
    final lastMessageSenderId = chat['lastMessageSenderId'];
// Mesaj gönderen kişiyi belirt
    if (lastMessageSenderId == currentUserId) {
      return 'Sen: $lastMessage';
    }
// Grup sohbeti için gönderenin adını göster
    if (chat['isGroup'] == true &&
        lastMessageSenderId != null &&
        lastMessageSenderId.isNotEmpty) {
      final senderProfile = userProfiles[lastMessageSenderId];
      final senderName = senderProfile?['username'] ?? 'Bilinmeyen';
      if (lastMessage.isNotEmpty) {
        return '$senderName: $lastMessage';
      }
    }
    return lastMessage;
  }

  String formatTime(Map<String, dynamic> chat) {
    final lastMessageTime = chat['lastMessageTime'];
    if (lastMessageTime == null) return '';
    final dateTime = lastMessageTime is Timestamp
        ? lastMessageTime.toDate()
        : DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    if (messageDate == today) {
// Bugün
      return DateFormat('HH:mm').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
// Dün
      return 'Dün';
    } else if (now.difference(dateTime).inDays < 7) {
// Son 7 gün içinde
      return DateFormat('E').format(dateTime); // Gün adı
    } else {
// Daha önce
      return DateFormat('dd.MM.yyyy').format(dateTime);
    }
  }

  int getUnreadCount(Map<String, dynamic> chat) {
    final unreadCount = chat['unreadCount'] as Map<String, dynamic>?;
    if (unreadCount == null || !unreadCount.containsKey(currentUserId)) {
      return 0;
    }
    return unreadCount[currentUserId] as int? ?? 0;
  }

  void showChatOptions(ChatModel chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chat.isGroup ? 'Grup İşlemleri' : 'Sohbet İşlemleri'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(chat.isGroup ? 'Grubu Sil' : 'Sohbeti Sil'),
              onTap: () {
                Navigator.pop(context);
                deleteChat(chat.chatId, chat.isGroup);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void navigateToChatDetail(
      BuildContext context, ChatModel chat, Map<String, dynamic> chatData) {
    if (chat.isGroup) {
      // chatData['groupId'] veya chat.groupId üzerinden gerçek groupId değerini bulun
      final realGroupId = chatData['groupId'] ?? '';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatDetailScreen(
            groupId: realGroupId, // Artık gerçek groupId'yi geçiyoruz
            groupName: chat.groupName ?? 'Grup',
            groupImageUrl: chat.groupImageUrl,
            chatId: chat.chatId,
          ),
        ),
      );
    } else {
      final participants = List<String>.from(chatData['participants'] ?? []);
      final otherParticipants =
          participants.where((id) => id != currentUserId).toList();
      if (otherParticipants.isEmpty) return;
      final receiverId = otherParticipants.first;
      final receiverProfile = userProfiles[receiverId];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chatId: chat.chatId,
            receiverId: receiverId,
            receiverName:
                receiverProfile?['username'] ?? 'Bilinmeyen Kullanıcı',
            receiverProfileImageUrl: receiverProfile?['profileImageUrl'] ?? '',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mesajlar'),
        ),
        body: const Center(
          child: Text('Oturum açmanız gerekiyor'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesajlar'),
        actions: [
// Grup oluşturma butonu
          IconButton(
            icon: const Icon(Icons.group_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateGroupScreen(),
                ),
              );
            },
          ),
// Yeni mesaj butonu
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NewChatScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(AppConstants.chatsCollection)
            .where('participants', arrayContains: currentUserId)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Bir hata oluştu: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Henüz bir sohbetiniz yok',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateGroupScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.group_add),
                        label: const Text('Grup Oluştur'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NewChatScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('Yeni Sohbet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          final chats = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ChatModel.fromSnapshot(doc);
          }).toList();
// Grup sohbetleri için grup üyelerinin profil bilgilerini yükle
          return FutureBuilder<void>(
            future: Future.wait(
              chats.map((chat) {
                if (chat.isGroup) {
// Grup sohbeti için son mesajı gönderen kişinin bilgilerini yükle
                  if (chat.lastMessageSenderId.isNotEmpty) {
                    return loadUserProfile(chat.lastMessageSenderId);
                  }
                  return Future.value();
                } else {
// Normal sohbet için alıcının bilgilerini yükle
                  final participants = chat.participants;
                  final otherParticipants =
                      participants.where((id) => id != currentUserId).toList();
                  if (otherParticipants.isEmpty) return Future.value();
                  return loadUserProfile(otherParticipants.first);
                }
              }),
            ),
            builder: (context, asyncSnapshot) {
              return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  final chatData =
                      snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  final isGroup = chat.isGroup;
                  return Dismissible(
                    key: Key(chat.chatId),
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20.0),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                      ),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(isGroup ? 'Grubu Sil' : 'Sohbeti Sil'),
                          content: Text(isGroup
                              ? 'Bu grubu silmek istediğinize emin misiniz? Tüm mesajlar silinecektir.'
                              : 'Bu sohbeti silmek istediğinize emin misiniz? Tüm mesajlar silinecektir.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('İptal'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sil',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (result == true) {
                        await deleteChat(chat.chatId, isGroup);
                      }
                      return result;
                    },
                    child: InkWell(
                      onTap: () =>
                          navigateToChatDetail(context, chat, chatData),
                      onLongPress: () => showChatOptions(chat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
// Profil/Grup resmi
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      isGroup ? Colors.blue[100] : null,
                                  backgroundImage:
                                      getProfileImageUrl(chatData).isNotEmpty
                                          ? CachedNetworkImageProvider(
                                              getProfileImageUrl(chatData))
                                          : null,
                                  child: getProfileImageUrl(chatData).isEmpty
                                      ? Icon(
                                          isGroup ? Icons.group : Icons.person)
                                      : null,
                                ),
                                if (isGroup)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.group,
                                        size: 14,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 16),
// Sohbet bilgileri
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        getReceiverName(chatData),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        formatTime(chatData),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          formatLastMessage(chatData),
                                          style: TextStyle(
                                            color: getUnreadCount(chatData) > 0
                                                ? Colors.black
                                                : Colors.grey[600],
                                            fontWeight:
                                                getUnreadCount(chatData) > 0
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (getUnreadCount(chatData) > 0)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF800000),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            getUnreadCount(chatData).toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
