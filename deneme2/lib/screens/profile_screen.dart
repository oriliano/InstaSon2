import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:instason/models/story_model.dart';
import 'package:instason/screens/add_story_screen.dart';
import 'package:instason/screens/chat_detail_screen.dart';
import 'package:instason/screens/comments_screen.dart';
import 'package:instason/screens/edit_profile_screen.dart';
import 'package:instason/screens/followers_screen.dart';
import 'package:instason/screens/following_screen.dart';
import 'package:instason/screens/login_screen.dart';
import 'package:instason/screens/post_detail_screen.dart';
import 'package:instason/screens/view_story_screen.dart';
import 'package:instason/utils/constants.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import 'package:instason/widgets/like_animation.dart';
import 'package:instason/widgets/post_card.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({Key? key, this.userId}) : super(key: key);
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<DocumentSnapshot> _posts = [];
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _isLoadingFollow = false;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  String _profileUserId = '';
  List<StoryModel> _userStories = [];
  bool _isLoadingStories = false;
  Map<String, dynamic> _profileData = {};
  // Çift tıklama animasyon durumlarını tutan map
  Map<String, bool> _doubleTapStates = {};

  @override
  void initState() {
    super.initState();
    _profileUserId = widget.userId ?? currentUserId ?? '';
    _loadUserData();
    _loadUserPosts();
    _checkFollowStatus();
    _loadUserStories();
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool get isCurrentUser => _profileUserId == currentUserId;

  void _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(_profileUserId)
          .get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.data() as Map<String, dynamic>;
        setState(() {
          _profileData = userData;
        });
        // Diğer asenkron işlemleri paralel olarak bekleyelim:
        await Future.wait([
          _getFollowCounts(),
          _loadUserPosts(),
          _loadUserStories(),
          _checkFollowStatus(),
        ]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı bulunamadı')),
        );
      }
    } catch (e) {
      print('Kullanıcı bilgileri yüklenirken hata oluştu: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserPosts() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .where('userId', isEqualTo: _profileUserId)
          .orderBy('createdAt', descending: true)
          .get();
      if (!mounted) return;
      setState(() {
        _posts = snapshot.docs;
      });
    } catch (e) {
      print('Gönderiler yüklenirken hata oluştu: $e');
    }
  }

  Future<void> _getFollowCounts() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(_profileUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final List<dynamic> rawFollowers = userData['followers'] ?? [];
        final List<dynamic> rawFollowing = userData['following'] ?? [];

        int validFollowersCount = 0;
        int validFollowingCount = 0;

        for (var followerId in rawFollowers) {
          final followerDoc = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(followerId)
              .get();
          if (followerDoc.exists) {
            validFollowersCount++;
          }
        }
        for (var followingId in rawFollowing) {
          final followingDoc = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(followingId)
              .get();
          if (followingDoc.exists) {
            validFollowingCount++;
          }
        }
        if (!mounted) return;
        setState(() {
          _followersCount = validFollowersCount;
          _followingCount = validFollowingCount;
        });
      }
    } catch (e) {
      print('Takipçi/takip edilen sayıları alınırken hata oluştu: $e');
    }
  }

  Future<void> _checkFollowStatus() async {
    if (currentUserId == null || isCurrentUser) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(_profileUserId)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (userData['followers'] != null && userData['followers'] is List) {
          final List<dynamic> followers =
              List<dynamic>.from(userData['followers']);
          setState(() {
            _isFollowing = followers.contains(currentUserId);
          });
        } else {
          setState(() {
            _isFollowing = false;
          });
        }
      }
    } catch (e) {
      print('Takip durumu kontrol edilirken hata oluştu: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (currentUserId == null || isCurrentUser) return;
    setState(() {
      _isLoadingFollow = true;
    });
    try {
      final userRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(_profileUserId);
      final currentUserRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId);
      final userDoc = await userRef.get();
      final currentUserDoc = await currentUserRef.get();
      if (!userDoc.exists || !currentUserDoc.exists) {
        throw Exception('Kullanıcı bulunamadı');
      }
      final userData = userDoc.data() as Map<String, dynamic>;
      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;

      List<dynamic> followers = userData['followers'] is List
          ? List<dynamic>.from(userData['followers'])
          : [];
      List<dynamic> following = currentUserData['following'] is List
          ? List<dynamic>.from(currentUserData['following'])
          : [];

      final batch = FirebaseFirestore.instance.batch();
      if (_isFollowing) {
        // Takibi bırak
        followers.remove(currentUserId);
        following.remove(_profileUserId);
        setState(() {
          _isFollowing = false;
          _followersCount = followers.length;
        });
      } else {
        // Takip et
        followers.add(currentUserId);
        following.add(_profileUserId);
        setState(() {
          _isFollowing = true;
          _followersCount = followers.length;
        });
        // Bildirim gönder
        await FirebaseFirestore.instance
            .collection(AppConstants.notificationsCollection)
            .add({
          'type': 'follow',
          'senderId': currentUserId,
          'senderUsername': currentUserData['username'],
          'senderProfileImageUrl': currentUserData['profileImageUrl'],
          'recipientId': _profileUserId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // Veritabanını güncelle
      batch.update(userRef, {'followers': followers});
      batch.update(currentUserRef, {'following': following});
      await batch.commit();
    } catch (e) {
      print('Takip işlemi sırasında hata oluştu: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Takip işlemi sırasında bir hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      setState(() {
        _isLoadingFollow = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('Çıkış yapılırken hata oluştu: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Çıkış yapılırken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<void> _loadUserStories() async {
    setState(() {
      _isLoadingStories = true;
    });
    try {
      final now = Timestamp.now();
      final storiesSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .where('userId', isEqualTo: _profileUserId)
          .where('expiresAt', isGreaterThan: now)
          .orderBy('expiresAt', descending: true)
          .orderBy('createdAt', descending: true)
          .get();
      final List<StoryModel> stories = [];
      for (var doc in storiesSnapshot.docs) {
        final data = doc.data();
        stories.add(StoryModel(
          storyId: doc.id,
          userId: data['userId'] ?? '',
          username: data['username'] ?? '',
          userProfileImageUrl: data['userProfileImageUrl'] ?? '',
          mediaUrl: data['mediaUrl'] ?? '',
          createdAt: (data['createdAt'] as Timestamp).toDate(),
          expiresAt: (data['expiresAt'] as Timestamp).toDate(),
          viewedBy: List<String>.from(data['viewedBy'] ?? []),
          isVideo: data['isVideo'] ?? false,
        ));
      }
      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _userStories = stories;
        _isLoadingStories = false;
      });
    } catch (e) {
      print('Hikayeler yüklenirken hata oluştu: $e');
      setState(() {
        _isLoadingStories = false;
      });
    }
  }

  // Ortak gönderi grid görünümü: Tek tıklama detay ekranına, çift tıklama like işlemi
  Widget _buildGridPosts() {
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isCurrentUser
                  ? 'Henüz gönderi paylaşmadınız'
                  : 'Bu kullanıcı henüz gönderi paylaşmamış',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _loadUserData();
        await _loadUserPosts();
        await _loadUserStories();
      },
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          if (index >= _posts.length) return const SizedBox.shrink();
          final postSnapshot = _posts[index];
          final post = postSnapshot.data() as Map<String, dynamic>;
          final postId = postSnapshot.id;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(
                    postId: postId,
                    initialPost: post,
                  ),
                ),
              ).then((_) {
                _loadUserData();
                _loadUserPosts();
              });
            },
            child: PostCard(
              post: post,
              postId: postId,
              onComment: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CommentsScreen(
                      postId: postId,
                      postUserId: post['userId'],
                      postImageUrl: post['mediaUrl'],
                    ),
                  ),
                );
              },
              onProfileTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                      userId: post['userId'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(_profileUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Kullanıcı bulunamadı'));
        }
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        _profileData = userData;
        final username = userData['username'] ?? 'Kullanıcı';
        final fullName = userData['fullName'] ?? '';
        final bio = userData['bio'] ?? '';
        final profileImageUrl = userData['profileImageUrl'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (profileImageUrl != null &&
                          profileImageUrl.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            child: Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: profileImageUrl,
                                  fit: BoxFit.contain,
                                ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.white),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF800000),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: (profileImageUrl != null &&
                                profileImageUrl.toString().isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: profileImageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const CircularProgressIndicator(),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.person),
                              )
                            : const Icon(Icons.person, size: 40),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem('Gönderi', _posts.length),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    FollowersScreen(userId: _profileUserId),
                              ),
                            );
                          },
                          child: _buildStatItem('Takipçi', _followersCount),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    FollowingScreen(userId: _profileUserId),
                              ),
                            );
                          },
                          child: _buildStatItem('Takip', _followingCount),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        bio,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: isCurrentUser
                  ? Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditProfileScreen(),
                                ),
                              ).then((_) => setState(() {}));
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Profili Düzenle'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF800000),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddStoryScreen(
                                  source: ImageSource.gallery,
                                ),
                              ),
                            ).then((_) => _loadUserStories());
                          },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Hikaye Ekle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF800000),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout, color: Colors.red),
                          tooltip: 'Çıkış Yap',
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _toggleFollow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFollowing
                                  ? Colors.grey[300]
                                  : const Color(0xFF800000),
                              foregroundColor:
                                  _isFollowing ? Colors.black : Colors.white,
                            ),
                            child: Text(
                                _isFollowing ? 'Takibi Bırak' : 'Takip Et'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            const Divider(),
          ],
        );
      },
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
                      Uri.tryParse(data['userProfileImageUrl'].toString())
                              ?.hasScheme ==
                          true
                  ? CachedNetworkImageProvider(data['userProfileImageUrl'])
                  : null,
              child: data['userProfileImageUrl'] == null ||
                      data['userProfileImageUrl'].toString().isEmpty ||
                      Uri.tryParse(data['userProfileImageUrl'].toString())
                              ?.hasScheme !=
                          true
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
                            builder: (context) =>
                                ProfileScreen(userId: data['userId']),
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
                      .collection(AppConstants.commentsCollection)
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
          .collection(AppConstants.commentsCollection)
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

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          _profileData['username'] ?? 'Profil',
          style: const TextStyle(
            color: Color(0xFF800000),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isLoading
            ? Center(
                key: const ValueKey('loading'),
                child:
                    CircularProgressIndicator(color: const Color(0xFF800000)),
              )
            : SingleChildScrollView(
                key: const ValueKey('content'),
                child: Column(
                  children: [
                    _buildProfileHeader(),
                    _buildGridPosts(),
                  ],
                ),
              ),
      ),
    );
  }
}
