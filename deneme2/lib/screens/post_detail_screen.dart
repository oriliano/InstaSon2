import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../utils/constants.dart';
import '../widgets/post_card.dart';
import '../widgets/comment_card.dart';
import 'profile_screen.dart';
import 'comments_screen.dart';
import '../widgets/custom_snackbar.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'followers_screen.dart';
import 'following_screen.dart';
import 'view_story_screen.dart';
import 'my_stories_screen.dart';
import '../models/story_model.dart';
import 'chat_detail_screen.dart';
import 'add_story_screen.dart';
import 'chat_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPost;

  const PostDetailScreen({
    Key? key,
    required this.postId,
    this.initialPost,
  }) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  bool _isPosting = false;
  bool _isLiked = false;
  int _likeCount = 0;
  StreamSubscription<DocumentSnapshot>? _postSubscription;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _postSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPost() async {
    try {
      if (widget.initialPost != null) {
        setState(() {
          _post = Map<String, dynamic>.from(widget.initialPost!);
          _isLoading = false;
        });
        _updateLikeStatus();
      }

      final postDoc = await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .get();

      if (postDoc.exists) {
        setState(() {
          _post = postDoc.data();
          _isLoading = false;
        });
        _updateLikeStatus();
        _subscribeToPostUpdates();
      } else {
        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gönderi bulunamadı'),
          ),
        );
      }
    } catch (e) {
      print('Gönderi yüklenirken hata oluştu: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _subscribeToPostUpdates() {
    _postSubscription = FirebaseFirestore.instance
        .collection(AppConstants.postsCollection)
        .doc(widget.postId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final updatedPost = snapshot.data();
        if (updatedPost != null) {
          setState(() {
            _post = updatedPost;
            _updateLikeStatus();
          });
        }
      }
    }, onError: (error) {
      print('Post güncellemelerini dinlerken hata: $error');
    });
  }

  void _updateLikeStatus() {
    if (_post == null || _post!['likes'] == null) {
      _isLiked = false;
      _likeCount = 0;
      return;
    }

    if (_post!['likes'] is List) {
      List<dynamic> likes = _post!['likes'];
      _isLiked = likes.contains(currentUserId);
      _likeCount = likes.length;
    } else if (_post!['likes'] is int) {
      _isLiked = false;
      _likeCount = _post!['likes'];
    } else {
      _isLiked = false;
      _likeCount = 0;
    }
  }

  bool _isPostLiked() {
    if (_post == null || _post!['likes'] == null || currentUserId == null) {
      return false;
    }

    if (_post!['likes'] is List) {
      List<dynamic> likes = _post!['likes'];
      return likes.contains(currentUserId);
    }

    return false;
  }

  int _getLikeCount() {
    if (_post == null || _post!['likes'] == null) {
      return 0;
    }

    if (_post!['likes'] is List) {
      List<dynamic> likes = _post!['likes'];
      return likes.length;
    } else if (_post!['likes'] is int) {
      return _post!['likes'];
    }

    return 0;
  }

  Future<void> _toggleLike() async {
    if (currentUserId == null || _post == null) return;

    // Önce UI'ı hemen güncelle (optimistik yaklaşım)
    final bool wasLiked = _isLiked;
    final List<String> likesTemp = 
        _post!['likes'] is List 
            ? List<String>.from(_post!['likes']) 
            : [];
    
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        if (!likesTemp.contains(currentUserId)) {
          likesTemp.add(currentUserId!);
        }
      } else {
        likesTemp.remove(currentUserId);
      }
      _likeCount = likesTemp.length;
      _post!['likes'] = likesTemp;
    });

    try {
      final postRef = FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId);

      final postDoc = await postRef.get();

      if (!postDoc.exists) {
        // Eğer post bulunamazsa, UI'ı eski haline getir
        setState(() {
          _isLiked = wasLiked;
          _updateLikeStatus();
        });
        return;
      }

      final postData = postDoc.data() as Map<String, dynamic>;

      // 'likes' alanını liste olarak al
      List<String> likes = [];
      if (postData['likes'] != null) {
        if (postData['likes'] is List) {
          likes = List<String>.from(postData['likes']);
        } else if (postData['likes'] is int) {
          // Eğer sayıysa, boş bir liste oluştur
          likes = [];
        }
      }

      if (wasLiked) {
        // Beğeniyi kaldır
        likes.remove(currentUserId);
      } else {
        // Beğen
        if (!likes.contains(currentUserId)) {
          likes.add(currentUserId!);

          // Gönderi sahibine bildirim gönder (kendisi değilse)
          if (postData['userId'] != currentUserId) {
            final userDoc = await FirebaseFirestore.instance
                .collection(AppConstants.usersCollection)
                .doc(currentUserId)
                .get();

            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;

              await FirebaseFirestore.instance
                  .collection(AppConstants.notificationsCollection)
                  .add({
                'type': 'like',
                'senderId': currentUserId,
                'senderUsername': userData['username'],
                'senderProfileImageUrl': userData['profileImageUrl'],
                'recipientId': postData['userId'],
                'postId': widget.postId,
                'postImageUrl': postData['mediaUrl'],
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }

      // Firestore'u güncelle
      await postRef.update({'likes': likes});

      // Son durumu kontrol et ve gerekirse yerel durumu güncelle
      if (mounted) {
        setState(() {
          _post!['likes'] = likes;
          _isLiked = likes.contains(currentUserId);
          _likeCount = likes.length;
        });
      }

    } catch (e) {
      print('Beğeni işlemi sırasında hata oluştu: $e');
      // Hata durumunda UI'ı eski haline getir
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _updateLikeStatus();
        });
      }
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
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const ListTile(
                              leading: CircleAvatar(
                                child: CircularProgressIndicator(),
                              ),
                              title: Text('Yükleniyor...'),
                            );
                          }

                          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                            return const ListTile(
                              leading: CircleAvatar(
                                child: Icon(Icons.error),
                              ),
                              title: Text('Kullanıcı bulunamadı'),
                            );
                          }

                          final userData = snapshot.data!.data() as Map<String, dynamic>;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: userData['profileImageUrl'] != null &&
                                  userData['profileImageUrl'].isNotEmpty
                                  ? CachedNetworkImageProvider(userData['profileImageUrl'])
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
                                  builder: (context) => ProfileScreen(userId: likerId),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gönderi'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_post == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gönderi'),
        ),
        body: const Center(
          child: Text('Gönderi bulunamadı'),
        ),
      );
    }

    final createdAt = _post!['createdAt'] != null
        ? (_post!['createdAt'] is Timestamp
            ? _post!['createdAt'].toDate()
            : DateTime.fromMillisecondsSinceEpoch(
                _post!['createdAt'].millisecondsSinceEpoch))
        : DateTime.now();

    final timeAgo = timeago.format(createdAt, locale: 'tr');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderi'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gönderi başlığı - kullanıcı bilgileri
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(
                                  userId: _post!['userId'],
                                ),
                              ),
                            );
                          },
                          child: CircleAvatar(
                            backgroundImage: (_post!['userProfileImageUrl'] !=
                                        null &&
                                    _post!['userProfileImageUrl'].isNotEmpty)
                                ? CachedNetworkImageProvider(
                                    _post!['userProfileImageUrl'],
                                  )
                                : null,
                            child: (_post!['userProfileImageUrl'] == null ||
                                    _post!['userProfileImageUrl'].isEmpty)
                                ? const Icon(Icons.person)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProfileScreen(
                                        userId: _post!['userId'],
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  _post!['username'] ?? 'Kullanıcı',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (_post!['location'] != null &&
                                  _post!['location'].isNotEmpty)
                                Text(
                                  _post!['location'],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () {
                            if (_post!['userId'] == currentUserId) {
                              _showDeletePostDialog();
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // Gönderi içeriği - medya
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                      ),
                      child: (_post!['mediaUrl'] != null &&
                              _post!['mediaUrl'].isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: _post!['mediaUrl'],
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) => const Center(
                                child: Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 50,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.image,
                                size: 50,
                                color: Colors.grey,
                              ),
                            ),
                    ),
                  ),

                  // Gönderi altı - etkileşim butonları
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        // Beğeni butonu
                        IconButton(
                          onPressed: _toggleLike,
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : null,
                            size: 28,
                          ),
                        ),
                        // Yorum butonu
                        IconButton(
                          onPressed: () {
                            // Yorum inputuna odaklan
                            FocusScope.of(context).requestFocus(FocusNode());
                          },
                          icon: const Icon(
                            Icons.comment_outlined,
                            size: 28,
                          ),
                        ),
                        // Paylaş butonu
                        IconButton(
                          onPressed: () {
                            // Paylaşma işlemi
                          },
                          icon: const Icon(
                            Icons.send_outlined,
                            size: 28,
                          ),
                        ),
                        const Spacer(),
                        // Kaydet butonu
                        IconButton(
                          onPressed: () {
                            // Kaydetme işlemi
                          },
                          icon: const Icon(
                            Icons.bookmark_border,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Beğeni sayısı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GestureDetector(
                      onTap: _showLikers,
                      child: Text(
                        '$_likeCount beğenme',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Gönderi açıklaması
                  if (_post!['caption'] != null && _post!['caption'].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 4.0),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black),
                          children: [
                            TextSpan(
                              text: '${_post!['username'] ?? 'Kullanıcı'} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: _post!['caption'],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Gönderi zamanı
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    child: Text(
                      timeAgo,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const Divider(),

                  // Yorumlar başlığı
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Yorumlar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),

                  // Yorumlar listesi
                  StreamBuilder<QuerySnapshot>(
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
                          child: Text('Hata: ${snapshot.error}'),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('Henüz yorum yok'),
                          ),
                        );
                      }

                      final comments = snapshot.data!.docs;
                      
                      // Client tarafında yorumları sıralıyoruz
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
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return _buildCommentItem(comment);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Yorum yapma alanı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[200],
                  child: const Icon(
                    Icons.person,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Yorum ekle...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isPosting
                      ? null
                      : () async {
                          if (_commentController.text.trim().isEmpty) return;

                          setState(() {
                            _isPosting = true;
                          });

                          try {
                            final currentUser =
                                FirebaseAuth.instance.currentUser;
                            if (currentUser == null) return;

                            final userDoc = await FirebaseFirestore.instance
                                .collection(AppConstants.usersCollection)
                                .doc(currentUser.uid)
                                .get();

                            if (!userDoc.exists) return;

                            final userData =
                                userDoc.data() as Map<String, dynamic>;

                            // Yorumu kaydet
                            final commentRef = await FirebaseFirestore.instance
                                .collection(AppConstants.commentsCollection)
                                .add({
                              'postId': widget.postId,
                              'userId': currentUser.uid,
                              'username': userData['username'],
                              'profileImageUrl': userData['profileImageUrl'],
                              'comment': _commentController.text.trim(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            // Gönderi sahibine bildirim gönder (kendisi değilse)
                            if (_post!['userId'] != currentUser.uid) {
                              await FirebaseFirestore.instance
                                  .collection(
                                      AppConstants.notificationsCollection)
                                  .add({
                                'type': 'comment',
                                'senderId': currentUser.uid,
                                'senderUsername': userData['username'],
                                'senderProfileImageUrl':
                                    userData['profileImageUrl'],
                                'recipientId': _post!['userId'],
                                'postId': widget.postId,
                                'postImageUrl': _post!['mediaUrl'],
                                'commentId': commentRef.id,
                                'commentText': _commentController.text.trim(),
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            }

                            // Yorum alanını temizle
                            setState(() {
                              _commentController.clear();
                              _isPosting = false;
                            });
                          } catch (e) {
                            print('Yorum eklenirken hata oluştu: $e');
                            setState(() {
                              _isPosting = false;
                            });
                          }
                        },
                  child: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Paylaş',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(DocumentSnapshot comment) {
    final data = comment.data() as Map<String, dynamic>;
    final isOwner = data['userId'] == currentUserId;
    final Timestamp? timestamp = data['createdAt'] as Timestamp?;
    final DateTime createdAt = timestamp?.toDate() ?? DateTime.now();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profil fotoğrafı
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: data['userId']),
                ),
              );
            },
            child: CircleAvatar(
              radius: 16,
              backgroundImage: data['userProfileImageUrl'] != null && 
                             data['userProfileImageUrl'].toString().isNotEmpty &&
                             Uri.tryParse(data['userProfileImageUrl'].toString())?.hasScheme == true
                  ? CachedNetworkImageProvider(data['userProfileImageUrl'])
                  : null,
              child: data['userProfileImageUrl'] == null || 
                     data['userProfileImageUrl'].toString().isEmpty ||
                     Uri.tryParse(data['userProfileImageUrl'].toString())?.hasScheme != true
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileScreen(userId: data['userId']),
                          ),
                        );
                      },
                      child: Text(
                        data['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeago.format(createdAt, locale: 'tr'),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  data['text'] ?? '',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _showReplyDialog(comment.id),
                      child: const Text(
                        'Yanıtla',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF800000),
                        ),
                      ),
                    ),
                    if (isOwner)
                      TextButton(
                        onPressed: () => _deleteComment(comment.id),
                        child: const Text(
                          'Sil',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
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
    );
  }

  Future<void> _showDeletePostDialog() async {
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

  Future<void> _deletePost() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Gönderiyi sil
      await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .delete();

      // Yorumları sil
      final commentsSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.commentsCollection)
          .where('postId', isEqualTo: widget.postId)
          .get();

      for (final doc in commentsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Bildirimleri sil
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.notificationsCollection)
          .where('postId', isEqualTo: widget.postId)
          .get();

      for (final doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gönderi başarıyla silindi'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Gönderi silinirken hata oluştu: $e');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gönderi silinirken bir hata oluştu: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}g önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}s önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}d önce';
    } else {
      return 'Şimdi';
    }
  }

  Future<void> _showReplyDialog(String commentId) async {
    final TextEditingController replyController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yanıtla'),
        content: TextField(
          controller: replyController,
          decoration: const InputDecoration(
            hintText: 'Yanıtınızı yazın...',
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
              if (replyController.text.trim().isNotEmpty) {
                try {
                  final userDoc = await FirebaseFirestore.instance
                      .collection(AppConstants.usersCollection)
                      .doc(currentUserId)
                      .get();
                  
                  final userData = userDoc.data() as Map<String, dynamic>;
                  
                  await FirebaseFirestore.instance
                      .collection(AppConstants.postsCollection)
                      .doc(widget.postId)
                      .collection('comments')
                      .doc(commentId)
                      .collection('replies')
                      .add({
                    'text': replyController.text.trim(),
                    'userId': currentUserId,
                    'username': userData['username'],
                    'userProfileImageUrl': userData['profileImageUrl'],
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  if (!mounted) return;
                  
                  Navigator.pop(context);
                  CustomSnackBar.show(
                    context: context,
                    message: 'Yanıtınız eklendi',
                    type: SnackBarType.success,
                  );
                } catch (e) {
                  print('Yanıt eklenirken hata oluştu: $e');
                  if (!mounted) return;
                  
                  CustomSnackBar.show(
                    context: context,
                    message: 'Yanıt eklenirken bir hata oluştu',
                    type: SnackBarType.error,
                  );
                }
              }
            },
            child: const Text('Yanıtla'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .delete();

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
} 