import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import 'dart:async';

import '../utils/constants.dart';

class ChatScreen extends StatefulWidget {
  final String recipientId;
  final String recipientUsername;
  final String? recipientProfileImageUrl;

  const ChatScreen({
    Key? key,
    required this.recipientId,
    required this.recipientUsername,
    this.recipientProfileImageUrl,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  bool _isLoading = false;
  bool _isTyping = false;
  Timer? _typingTimer;

  @override
  void dispose() {
    _messageController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _updateTypingStatus(bool isTyping) {
    if (currentUserId == null) return;

    setState(() {
      _isTyping = isTyping;
    });

    // Yazıyor durumunu Firestore'a kaydet
    FirebaseFirestore.instance
        .collection(AppConstants.chatsCollection)
        .doc('${currentUserId}_${widget.recipientId}')
        .update({
      'typingUsers': isTyping
          ? FieldValue.arrayUnion([currentUserId])
          : FieldValue.arrayRemove([currentUserId])
    });

    // 3 saniye sonra yazıyor durumunu kaldır
    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _updateTypingStatus(false);
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final message = _messageController.text.trim();
      _messageController.clear();

      // Mesajı Firestore'a kaydet
      final messageRef = await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .add({
        'senderId': currentUserId,
        'recipientId': widget.recipientId,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'participants': [currentUserId, widget.recipientId],
        'status': 'sent',
      });

      // Mesaj durumunu güncelle
      await messageRef.update({
        'status': 'delivered',
      });

      // Bildirim gönder
      await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .add({
        'recipientId': widget.recipientId,
        'senderId': currentUserId,
        'type': 'message',
        'message': message,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Mesaj gönderilirken hata: $e');
      if (context.mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Mesaj gönderilemedi',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .delete();

      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Mesaj silindi',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      print('Mesaj silinirken hata: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Mesaj silinirken bir hata oluştu',
          type: SnackBarType.error,
        );
      }
    }
  }

  void _editMessage(String messageId, String currentText) {
    final TextEditingController editController =
        TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı Düzenle'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(
            hintText: 'Mesajınızı düzenleyin...',
            border: OutlineInputBorder(),
          ),
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (editController.text.trim().isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection(AppConstants.messagesCollection)
                      .doc(messageId)
                      .update({
                    'message': editController.text.trim(),
                    'edited': true,
                    'editedAt': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    CustomSnackBar.show(
                      context: context,
                      message: 'Mesaj düzenlendi',
                      type: SnackBarType.success,
                    );
                  }
                } catch (e) {
                  print('Mesaj düzenlenirken hata: $e');
                  if (mounted) {
                    CustomSnackBar.show(
                      context: context,
                      message: 'Mesaj düzenlenirken bir hata oluştu',
                      type: SnackBarType.error,
                    );
                  }
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(String messageId, String messageText, bool isMe) {
    if (!isMe) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Düzenle'),
              onTap: () {
                Navigator.pop(context);
                _editMessage(messageId, messageText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Sil', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(messageId);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.recipientProfileImageUrl != null
                  ? CachedNetworkImageProvider(widget.recipientProfileImageUrl!)
                  : null,
              child: widget.recipientProfileImageUrl == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.recipientUsername),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection(AppConstants.chatsCollection)
                        .doc('${widget.recipientId}_${currentUserId}')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();

                      final data =
                          snapshot.data?.data() as Map<String, dynamic>?;
                      final typingUsers =
                          List<String>.from(data?['typingUsers'] ?? []);
                      final isTyping = typingUsers.contains(widget.recipientId);

                      return Text(
                        isTyping ? 'Yazıyor...' : '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.messagesCollection)
                  .where('participants', arrayContains: currentUserId)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Bir hata oluştu'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs.where((doc) {
                  final message = doc.data() as Map<String, dynamic>;
                  return (message['senderId'] == currentUserId &&
                          message['recipientId'] == widget.recipientId) ||
                      (message['senderId'] == widget.recipientId &&
                          message['recipientId'] == currentUserId);
                }).toList();

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == currentUserId;
                    final messageId = messages[index].id;

                    return GestureDetector(
                      onLongPress: () => _showMessageOptions(
                        messageId,
                        message['message'],
                        isMe,
                      ),
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF800000)
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                message['message'],
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (message['edited'] == true)
                                      const Text(
                                        'Düzenlendi',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      message['isRead'] == true
                                          ? Icons.done_all
                                          : message['status'] == 'delivered'
                                              ? Icons.done_all
                                              : Icons.done,
                                      size: 16,
                                      color: message['isRead'] == true
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                    onChanged: (text) {
                      _updateTypingStatus(text.isNotEmpty);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
