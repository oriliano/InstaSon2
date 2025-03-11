import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../screens/comments_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/chat_screen.dart';
import '../utils/constants.dart';
import '../widgets/like_animation.dart';
import '../widgets/custom_snackbar.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  final VoidCallback? onDelete;
  final VoidCallback? onComment;
  final VoidCallback? onProfileTap;
  final IconButton? trailing;

  const PostCard({
    Key? key,
    required this.post,
    required this.postId,
    this.onDelete,
    this.onComment,
    this.onProfileTap,
    this.trailing,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isLiked = false;
  int _likeCount = 0;
  final _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  bool _isDoubleTapLiking = false;
  int _commentCount = 0;
  late Map<String, dynamic> post;
  StreamSubscription? _likeSubscription;
  StreamSubscription? _commentSubscription;
  List<Map<String, dynamic>> _comments = [];

  @override
  void initState() {
    super.initState();
    post = Map<String, dynamic>.from(widget.post);
    _initializeLikeStatus();
    _setupLikeListener();
    _setupCommentListener();
  }

  @override
  void dispose() {
    _likeSubscription?.cancel();
    _commentSubscription?.cancel();
    super.dispose();
  }

  void _initializeLikeStatus() {
    if (widget.post['likes'] != null) {
      if (widget.post['likes'] is List) {
        final likes = List<String>.from(widget.post['likes']);
        setState(() {
          _isLiked = likes.contains(_currentUserId);
          _likeCount = likes.length;
        });
      }
    }
  }

  void _setupLikeListener() {
    _likeSubscription = FirebaseFirestore.instance
        .collection(AppConstants.postsCollection)
        .doc(widget.postId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['likes'] != null && data['likes'] is List) {
          final likes = List<String>.from(data['likes']);
          setState(() {
            _isLiked = likes.contains(_currentUserId);
            _likeCount = likes.length;
          });
        }
      }
    });
  }

  void _setupCommentListener() {
    _commentSubscription = FirebaseFirestore.instance
        .collection(AppConstants.commentsCollection)
        .where('postId', isEqualTo: widget.postId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _commentCount = snapshot.docs.length;
          _comments = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              ...data,
              'commentId': doc.id,
            };
          }).toList();
        });
      }
    });
  }

  Future<void> _toggleLike() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    try {
      final postRef = FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId);

      final postDoc = await postRef.get();
      if (!postDoc.exists) return;

      List<String> likes = [];
      if (postDoc.data()?['likes'] != null) {
        likes = List<String>.from(postDoc.data()?['likes']);
      }

      if (_isLiked) {
        if (!likes.contains(_currentUserId)) {
          likes.add(_currentUserId!);
        }
      } else {
        likes.remove(_currentUserId);
      }

      await postRef.update({'likes': likes});

      // Bildirim gönder
      if (_isLiked && widget.post['userId'] != _currentUserId) {
        final currentUserDoc = await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(_currentUserId)
            .get();

        if (currentUserDoc.exists) {
          final currentUserData = currentUserDoc.data() as Map<String, dynamic>;

          await FirebaseFirestore.instance
              .collection(AppConstants.notificationsCollection)
              .add({
            'type': 'like',
            'postId': widget.postId,
            'postImageUrl': widget.post['mediaUrl'],
            'senderId': _currentUserId,
            'senderUsername': currentUserData['username'],
            'senderProfileImageUrl': currentUserData['profileImageUrl'],
            'recipientId': widget.post['userId'],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('Beğeni işlemi sırasında hata oluştu: $e');
      // Hata durumunda UI'ı eski haline getir
      setState(() {
        _isLiked = !_isLiked;
        _likeCount += _isLiked ? 1 : -1;
      });
    }
  }

  Future<void> _showLikers() async {
    if (_likeCount == 0) return;

    try {
      final postDoc = await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .get();

      if (!postDoc.exists) return;

      final postData = postDoc.data() as Map<String, dynamic>;

      // Beğenenler listesini al
      List<String> likerIds = [];
      if (postData['likes'] != null && postData['likes'] is List) {
        likerIds = List<String>.from(postData['likes']);
      }

      if (likerIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Henüz kimse beğenmemiş')),
        );
        return;
      }

      // Beğenenleri göster
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Beğenenler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: likerIds.length,
                    itemBuilder: (context, index) {
                      final likerId = likerIds[index];

                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection(AppConstants.usersCollection)
                            .doc(likerId)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const ListTile(
                              leading: CircleAvatar(
                                child: CircularProgressIndicator(),
                              ),
                              title: Text('Yükleniyor...'),
                            );
                          }

                          if (snapshot.hasError ||
                              !snapshot.hasData ||
                              !snapshot.data!.exists) {
                            return const ListTile(
                              leading: CircleAvatar(
                                child: Icon(Icons.error),
                              ),
                              title: Text('Kullanıcı bulunamadı'),
                            );
                          }

                          final userData =
                              snapshot.data!.data() as Map<String, dynamic>;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  userData['profileImageUrl'] != null &&
                                          userData['profileImageUrl'].isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          userData['profileImageUrl'])
                                      : null,
                              child: userData['profileImageUrl'] == null ||
                                      userData['profileImageUrl'].isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              userData['username'] ?? 'Kullanıcı',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              userData['fullName'] ?? '',
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProfileScreen(userId: likerId),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      print('Beğenenler yüklenirken hata oluştu: $e');
    }
  }

  String _getTimeAgo() {
    if (widget.post['createdAt'] == null) return '';

    DateTime dateTime;
    if (widget.post['createdAt'] is Timestamp) {
      dateTime = widget.post['createdAt'].toDate();
    } else {
      dateTime = DateTime.fromMillisecondsSinceEpoch(
          widget.post['createdAt'].millisecondsSinceEpoch);
    }

    return timeago.format(dateTime, locale: 'tr');
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Gönderiyi Sil',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Gönderiyi Düzenle'),
                onTap: () {
                  _showEditDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deletePost() async {
    try {
      // Önce yorumları sil
      final commentsSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.commentsCollection)
          .where('postId', isEqualTo: widget.postId)
          .get();

      // Tüm yorumları sil
      for (var doc in commentsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Gönderiyi sil
      await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .delete();

      // Medya dosyasını sil (eğer varsa)
      if (post['mediaUrl'] != null) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(post['mediaUrl']);
          await ref.delete();
        } catch (e) {
          print('Medya dosyası silinirken hata oluştu: $e');
        }
      }

      // Bildirimleri sil
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .where('postId', isEqualTo: widget.postId)
          .get();

      for (var doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Gönderi silindi',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      print('Gönderi silinirken hata oluştu: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Gönderi silinirken bir hata oluştu',
          type: SnackBarType.error,
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Sil'),
        content: const Text('Bu gönderiyi silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePost();
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog() {
    final TextEditingController captionController =
        TextEditingController(text: post['caption']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Düzenle'),
        content: TextField(
          controller: captionController,
          decoration: const InputDecoration(
            hintText: 'Açıklama',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection(AppConstants.postsCollection)
                    .doc(post['postId'])
                    .update({
                  'caption': captionController.text,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gönderi güncellendi')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Gönderi güncellenirken bir hata oluştu')),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = post['userId'] == _currentUserId;

    return GestureDetector(
      onDoubleTap: () async {
        if (!_isDoubleTapLiking) {
          _isDoubleTapLiking = true;
          if (!_isLiked) {
            await _toggleLike();
          }
          setState(() {});
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst kısım - Kullanıcı bilgileri
            ListTile(
              leading: GestureDetector(
                onTap: widget.onProfileTap ?? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        userId: post['userId'],
                      ),
                    ),
                  );
                },
                child: CircleAvatar(
                  backgroundImage: post['userProfileImageUrl'] != null && 
                                 post['userProfileImageUrl'].toString().isNotEmpty &&
                                 Uri.tryParse(post['userProfileImageUrl'].toString())?.hasScheme == true
                        ? CachedNetworkImageProvider(post['userProfileImageUrl'])
                        : null,
                  child: post['userProfileImageUrl'] == null || 
                         post['userProfileImageUrl'].toString().isEmpty ||
                         Uri.tryParse(post['userProfileImageUrl'].toString())?.hasScheme != true
                        ? const Icon(Icons.person)
                        : null,
                ),
              ),
              title: GestureDetector(
                onTap: widget.onProfileTap ?? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        userId: post['userId'],
                      ),
                    ),
                  );
                },
                child: Text(
                  post['username'] ?? 'Kullanıcı',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              subtitle: Text(
                _getTimeAgo(),
                style: TextStyle(color: Colors.grey[600]),
              ),
              trailing: isOwner
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          _showDeleteConfirmation();
                        } else if (value == 'edit') {
                          _showEditDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Düzenle'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Sil'),
                        ),
                      ],
                    )
                  : null,
            ),

            // Görsel
            GestureDetector(
              onDoubleTap: () async {
                if (!_isDoubleTapLiking) {
                  _isDoubleTapLiking = true;
                  if (!_isLiked) {
                    await _toggleLike();
                  }
                  setState(() {});
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Gönderi görseli
                  Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.width,
                    ),
                    width: double.infinity,
                    child: (post['mediaUrl'] != null)
                        ? CachedNetworkImage(
                            imageUrl: post['mediaUrl'],
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.error),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.image, size: 50, color: Colors.grey),
                          ),
                  ),

                  // Beğeni animasyonu
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isDoubleTapLiking ? 1 : 0,
                    child: LikeAnimation(
                      isAnimating: _isDoubleTapLiking,
                      duration: const Duration(milliseconds: 400),
                      onEnd: () {
                        setState(() {
                          _isDoubleTapLiking = false;
                        });
                      },
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 100,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Alt kısım - Etkileşim butonları ve yorumlar
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isLiked ? Icons.favorite : Icons.favorite_border,
                      color: _isLiked ? Colors.red : null,
                    ),
                    onPressed: _toggleLike,
                  ),
                  IconButton(
                    icon: const Icon(Icons.comment_outlined),
                    onPressed: widget.onComment,
                  ),
                ],
              ),
            ),

            // Beğeni sayısı ve yorum sayısı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _showLikers,
                    child: Text(
                      '$_likeCount beğenme',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_commentCount > 0)
                    GestureDetector(
                      onTap: widget.onComment,
                      child: Text(
                        '$_commentCount yorum',
                        style: const TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Son yorumlar
            if (_comments.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: '${_comments[0]['username'] ?? 'Kullanıcı'} ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: _comments[0]['text'] ?? '',
                      ),
                      if (_commentCount > 1)
                        TextSpan(
                          text: ' ve $_commentCount yorum daha',
                          style: const TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // Açıklama
            if (post['caption'] != null && post['caption'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: RichText(
                  maxLines: null,
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: '${post['username'] ?? 'Kullanıcı'} ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: post['caption'],
                      ),
                    ],
                  ),
                ),
              ),

            // Zaman
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Text(
                _getTimeAgo(),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
