import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:instason/screens/group_chat_detail_screen.dart';
import '../utils/constants.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_snackbar.dart';
import 'profile_screen.dart';
import 'post_detail_screen.dart';
import 'chat_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  String _selectedFilter =
      'all'; // 'all', 'unread', 'messages', 'likes', 'comments'
  bool _isLoading = false;

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else {
      dateTime =
          DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch);
    }

    return timeago.format(dateTime, locale: 'tr');
  }

  Future<void> _markAsRead(String notificationId) async {
    await FirebaseFirestore.instance
        .collection(AppConstants.notificationsCollection)
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> _markAllAsRead() async {
    if (currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final notifications = await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .where('recipientId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in notifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Tüm bildirimler okundu olarak işaretlendi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Bildirimler okundu olarak işaretlenirken hata: $e');
      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Bir hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .doc(notificationId)
          .delete();

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Bildirim silindi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Bildirim silinirken hata: $e');
      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Bildirim silinirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  void _showDeleteConfirmation(String notificationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bildirimi Sil'),
        content: const Text('Bu bildirimi silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteNotification(notificationId);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Tümü'),
            selected: _selectedFilter == 'all',
            onSelected: (selected) {
              setState(() {
                _selectedFilter = 'all';
              });
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Okunmuş'),
            selected: _selectedFilter == 'unread',
            onSelected: (selected) {
              setState(() {
                _selectedFilter = 'unread';
              });
            },
          ),
        ],
      ),
    );
  }

  Color _getNotificationColor(bool isRead) {
    return isRead ? Colors.transparent : Colors.red.withOpacity(0.1);
  }

  Widget _buildNotificationIcon(String type) {
    // Bu metot S-ADE-CE tipten gelen ikonu ve rengi ayarlasın.
    IconData iconData;
    Color iconColor;

    // Her case'te hem iconData hem iconColor set edilmeli:
    switch (type) {
      case 'like':
        iconData = Icons.favorite;
        iconColor = Colors.red;
        break;
      case 'comment':
        iconData = Icons.comment;
        iconColor = Colors.blue;
        break;
      case 'follow':
        iconData = Icons.person_add;
        iconColor = Colors.green;
        break;
      case 'message':
        iconData = Icons.message;
        iconColor = Colors.purple;
        break;
      case 'group_message':
        // Grup mesajı için ikon
        iconData = Icons.group;
        iconColor = Colors.brown;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = Colors.orange;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 20,
      ),
    );
  }

  Widget _buildNotificationItem(
      Map<String, dynamic> notification, String notificationId) {
    String message;

    switch (notification['type']) {
      case 'like':
        message = '${notification['senderUsername']} gönderini beğendi';
        break;
      case 'comment':
        message =
            '${notification['senderUsername']} gönderine yorum yaptı: ${notification['content']}';
        break;
      case 'follow':
        message = '${notification['senderUsername']} seni takip etmeye başladı';
        break;
      case 'message':
        message =
            '${notification['senderUsername']} sana mesaj gönderdi: ${notification['content']}';
        break;
      default:
        message = '${notification['senderUsername']} Storyini gördü ';
    }

    final bool isRead = notification['isRead'] ?? false;

    return Dismissible(
      key: Key(notificationId),
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
      onDismissed: (direction) {
        _deleteNotification(notificationId);
      },
      child: GestureDetector(
        onLongPress: () {
          _showDeleteConfirmation(notificationId);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: _getNotificationColor(isRead),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (notification['senderId'] != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProfileScreen(userId: notification['senderId']),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[200],
                    backgroundImage:
                        _isValidImageUrl(notification['senderProfileImageUrl'])
                            ? CachedNetworkImageProvider(
                                notification['senderProfileImageUrl'] as String)
                            : null,
                    child: !_isValidImageUrl(
                            notification['senderProfileImageUrl'])
                        ? const Icon(Icons.person, size: 24, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                _buildNotificationIcon(notification['type']),
              ],
            ),
            title: Text(
              message,
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                fontSize: 14,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _getTimeAgo(notification['createdAt']),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
            trailing: notification['type'] == 'like' ||
                    notification['type'] == 'comment'
                ? notification['postImageUrl'] != null &&
                        notification['postImageUrl'].isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          if (notification['postId'] != null) {
                            _markAsRead(notificationId);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PostDetailScreen(
                                    postId: notification['postId']),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: CachedNetworkImageProvider(
                                  notification['postImageUrl']),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      )
                    : null
                : null,
            onTap: () async {
              await _markAsRead(notificationId);

              if (!mounted) return;

              switch (notification['type']) {
                case 'like':
                case 'comment':
                  if (notification['postId'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PostDetailScreen(postId: notification['postId']),
                      ),
                    );
                  }
                  break;
                case 'follow':
                  if (notification['senderId'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfileScreen(userId: notification['senderId']),
                      ),
                    );
                  }
                  break;
                case 'message':
                  if (notification['senderId'] != null &&
                      notification['senderUsername'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatDetailScreen(
                          receiverId: notification['senderId'],
                          receiverName: notification['senderUsername'],
                          receiverProfileImageUrl:
                              notification['senderProfileImageUrl'] ?? '',
                        ),
                      ),
                    );
                  }
                  break;
              }
            },
          ),
        ),
      ),
    );
  }

  bool _isValidImageUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    if (urlStr.isEmpty) return false;
    try {
      final uri = Uri.parse(urlStr);
      return uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(
          child: Text('Oturum açmanız gerekiyor'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.done_all),
            onPressed: _isLoading ? null : _markAllAsRead,
          ),
        ],
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.notificationsCollection)
                  .where('recipientId', isEqualTo: currentUserId)
                  .where('isRead', isEqualTo: _selectedFilter == 'unread')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bir hata oluştu\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Henüz bildiriminiz yok',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final notification = doc.data() as Map<String, dynamic>;

                    return _buildNotificationItem(notification, doc.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
