import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../screens/profile_screen.dart';
import '../utils/constants.dart';

class CommentCard extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String commentId;
  final String postId;
  final String postOwnerId;

  const CommentCard({
    Key? key,
    required this.comment,
    required this.commentId,
    required this.postId,
    required this.postOwnerId,
  }) : super(key: key);

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  bool _isDeleting = false;

  String _getTimeAgo() {
    if (widget.comment['createdAt'] == null) return '';
    
    DateTime dateTime;
    if (widget.comment['createdAt'] is Timestamp) {
      dateTime = widget.comment['createdAt'].toDate();
    } else {
      dateTime = DateTime.fromMillisecondsSinceEpoch(
          widget.comment['createdAt'].millisecondsSinceEpoch);
    }
    
    return timeago.format(dateTime, locale: 'tr');
  }

  void _deleteComment() async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      // Yorumu sil
      await FirebaseFirestore.instance
          .collection(AppConstants.commentsCollection)
          .doc(widget.commentId)
          .delete();

      // Bildirim varsa sil
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .where('type', isEqualTo: 'comment')
          .where('commentId', isEqualTo: widget.commentId)
          .get();

      for (var doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Silindikten sonra state'i güncelle
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    } catch (e) {
      print('Yorum silinirken hata oluştu: $e');
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum silinirken bir hata oluştu')),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yorumu Sil'),
        content: const Text('Bu yorumu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteComment();
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCommentOwner = widget.comment['userId'] == currentUserId;
    final bool isPostOwner = widget.postOwnerId == currentUserId;
    final bool canDelete = isCommentOwner || isPostOwner;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kullanıcı profil resmi
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    userId: widget.comment['userId'],
                  ),
                ),
              );
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[200],
              backgroundImage: (widget.comment['userProfileImageUrl'] != null &&
                      widget.comment['userProfileImageUrl'].isNotEmpty)
                  ? CachedNetworkImageProvider(widget.comment['userProfileImageUrl'])
                  : null,
              child: (widget.comment['userProfileImageUrl'] == null ||
                      widget.comment['userProfileImageUrl'].isEmpty)
                  ? const Icon(Icons.person, size: 18, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Yorum içeriği
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: widget.comment['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: widget.comment['text'] ?? '',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _getTimeAgo(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    /*
                    GestureDetector(
                      onTap: () {
                        // Yanıtla işlevi
                      },
                      child: const Text(
                        'Yanıtla',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    */
                  ],
                ),
              ],
            ),
          ),
          // Silme butonu
          if (canDelete)
            _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.grey,
                    onPressed: _showDeleteDialog,
                  ),
        ],
      ),
    );
  }
} 