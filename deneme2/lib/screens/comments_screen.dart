import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/widgets/comment_card.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'profile_screen.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPost;
  final String? postUserId; // Gönderi sahibinin kullanıcı ID'si
  final String? postImageUrl; // Eksik parametre eklendi

  const CommentsScreen({
    Key? key,
    required this.postId,
    this.initialPost,
    this.postUserId,
    this.postImageUrl,
  }) : super(key: key);

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode(); // Eksik FocusNode eklendi
  bool _isLoading = false;
  Map<String, dynamic>? _postData;
  Map<String, Map<String, dynamic>> _userDataCache = {};
  String? _postUserId; // Gönderi sahibinin kullanıcı ID'si

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _postData = widget.initialPost;
      _postUserId = widget.initialPost!['userId'];
    } else {
      _loadPostData();
    }

    // Kullanıcı verilerini yükle
    if (currentUserId != null) {
      _getUserData(currentUserId!);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose(); // FocusNode temizlenmesi
    super.dispose();
  }

  Future<void> _loadPostData() async {
    try {
      final postDoc = await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .get();

      if (postDoc.exists) {
        final data = postDoc.data() as Map<String, dynamic>;
        setState(() {
          _postData = data;
          _postUserId = data['userId'];
        });
      }
    } catch (e) {
      print('Gönderi yüklenirken hata oluştu: $e');
    }
  }

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    if (_userDataCache.containsKey(userId)) {
      return _userDataCache[userId];
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        _userDataCache[userId] = userData;
        return userData;
      }
    } catch (e) {
      print('Kullanıcı bilgileri yüklenirken hata oluştu: $e');
    }

    return null;
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) {
      CustomSnackBar.show(
        context: context,
        message: 'Yorum boş olamaz',
        type: SnackBarType.warning,
      );
      return;
    }

    if (currentUserId == null) {
      CustomSnackBar.show(
        context: context,
        message: 'Yorum yapmak için giriş yapmanız gerekiyor',
        type: SnackBarType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Kullanıcı bilgilerini al
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (!userDoc.exists) {
        throw Exception('Kullanıcı bulunamadı');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final String username = userData['username'] ?? '';
      final String profileImageUrl = userData['profileImageUrl'] ?? '';

      // Yorumu ekle
      final commentRef = await FirebaseFirestore.instance
          .collection(AppConstants.commentsCollection)
          .add({
        'postId': widget.postId,
        'userId': currentUserId,
        'username': username,
        'userProfileImageUrl': profileImageUrl,
        'text': _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'likes': [],
      });

      // Gönderi yorum sayısını güncelle
      final postRef = FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postDoc = await transaction.get(postRef);

        if (!postDoc.exists) {
          throw Exception('Gönderi bulunamadı');
        }

        final int currentComments = postDoc.data()?['comments'] ?? 0;
        transaction.update(postRef, {'comments': currentComments + 1});
      });

      // Post sahibine bildirim gönder (kendi postuna yorum yapmadıysa)
      if (widget.postUserId != currentUserId) {
        await FirebaseFirestore.instance
            .collection(AppConstants.notificationsCollection)
            .add({
          'type': 'comment',
          'postId': widget.postId,
          'postImageUrl': widget.postImageUrl,
          'senderId': currentUserId,
          'senderUsername': username,
          'senderProfileImageUrl': profileImageUrl,
          'recipientId': widget.postUserId,
          'content': _commentController.text.trim().length > 50
              ? '${_commentController.text.trim().substring(0, 50)}...'
              : _commentController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }

      if (!mounted) return;

      // Input temizle ve klavyeyi kapat
      _commentController.clear();
      FocusScope.of(context).unfocus();

      CustomSnackBar.show(
        context: context,
        message: 'Yorum eklendi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Yorum eklenirken hata oluştu: $e');

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Yorum eklenirken bir hata oluştu',
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

  Future<void> _deleteComment(String commentId) async {
    try {
      // Doğru koleksiyon yolunu kullanıyoruz
      await FirebaseFirestore.instance
          .collection(AppConstants.commentsCollection)
          .doc(commentId)
          .delete();

      // Gönderi yorum sayısını güncelle
      final postRef = FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postDoc = await transaction.get(postRef);

        if (!postDoc.exists) {
          throw Exception('Gönderi bulunamadı');
        }

        final int currentComments = postDoc.data()?['comments'] ?? 0;
        if (currentComments > 0) {
          transaction.update(postRef, {'comments': currentComments - 1});
        }
      });

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Yorum silindi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Yorum silinirken hata oluştu: $e');

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Yorum silinirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yorumlar'),
      ),
      body: Column(
        children: [
          // Yorumlar
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.commentsCollection)
                  .where('postId', isEqualTo: widget.postId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Bir hata oluştu: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Henüz yorum yok'),
                  );
                }

                final comments = snapshot.data!.docs;

                // Yorumları client tarafında sıralıyoruz
                comments.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;

                  final aTime = aData['createdAt'] as Timestamp?;
                  final bTime = bData['createdAt'] as Timestamp?;

                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;

                  return bTime.compareTo(aTime); // Yeniden eskiye sıralama
                });

                return ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final commentDoc = comments[index];
                    return _buildCommentItem(commentDoc);
                  },
                );
              },
            ),
          ),

          // Yorum ekleme
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: currentUserId != null &&
                          _userDataCache.containsKey(currentUserId) &&
                          _userDataCache[currentUserId]!['profileImageUrl'] !=
                              null &&
                          _userDataCache[currentUserId]!['profileImageUrl']
                              .isNotEmpty
                      ? CachedNetworkImageProvider(
                          _userDataCache[currentUserId]!['profileImageUrl'])
                      : null,
                  child: currentUserId == null ||
                          !_userDataCache.containsKey(currentUserId) ||
                          _userDataCache[currentUserId]!['profileImageUrl'] ==
                              null ||
                          _userDataCache[currentUserId]!['profileImageUrl']
                              .isEmpty
                      ? const Icon(Icons.person, size: 16, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: currentUserId != null
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProfileScreen(userId: currentUserId!),
                              ),
                            );
                          }
                        : null,
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: 'Yorum ekle...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                    ),
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isLoading ? null : _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(DocumentSnapshot commentDoc) {
    final comment = commentDoc.data() as Map<String, dynamic>;
    final String commenterId = comment['userId'] ?? '';
    final String commentText = comment['text'] ?? '';
    final Timestamp? timestamp = comment['createdAt'] as Timestamp?;
    final DateTime createdAt = timestamp?.toDate() ?? DateTime.now();
    // Yorum belgesinde saklanan profil fotoğrafı URL'si
    String? profileImageUrl = comment['userProfileImageUrl'];
    final String username = comment['username'] ?? 'Kullanıcı';

    // Her zaman kullanıcı verilerini çekiyoruz, böylece güncel profil fotoğrafını alıyoruz.
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getUserData(commenterId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          // Eğer güncel kullanıcı verisi geldiyse, profil fotoğrafını güncelliyoruz.
          profileImageUrl =
              snapshot.data?['profileImageUrl'] ?? profileImageUrl;
        }
        return CommentCard(
          comment: {
            'userId': commenterId,
            'username': username,
            'text': commentText,
            'userProfileImageUrl': profileImageUrl,
            'createdAt': timestamp,
          },
          commentId: commentDoc.id,
          postId: widget.postId,
          postOwnerId: widget.postUserId ?? '',
        );
      },
    );
  }
}
