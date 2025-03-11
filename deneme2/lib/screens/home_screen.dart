import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import 'dart:async'; // StreamSubscription tipini kullanabilmek için eklendi

import '../utils/constants.dart';
import '../widgets/post_card.dart';
import '../models/story_model.dart';
import '../screens/add_story_screen.dart';
import '../screens/view_story_screen.dart';
import '../screens/my_stories_screen.dart';
import '../screens/add_post_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/search_screen.dart';
import '../screens/comments_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  List<QueryDocumentSnapshot> _posts = [];
  Map<String, List<StoryModel>> _stories = {};
  bool _isLoadingPosts = true;
  bool _isLoadingStories = true;
  Timer? _storyRefreshTimer;
  StreamSubscription? _postsSubscription;
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadStories();
    _loadPosts();
    _loadUsers();

    // Hikayeleri her dakika yenile (süresi dolanları kaldırmak için)
    _storyRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadStories();
    });
  }

  @override
  void dispose() {
    _storyRefreshTimer?.cancel();
    _postsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStories() async {
    if (currentUserId == null) return;

    setState(() {
      _isLoadingStories = true;
    });

    try {
      // Kullanıcının takip ettiği kişileri al
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (!userDoc.exists) {
        setState(() {
          _isLoadingStories = false;
        });
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final List<dynamic> following = userData['following'] ?? [];

      // Kullanıcının kendi ID'sini de ekle (kendi hikayelerini de görmesi için)
      final userIds = [...following, currentUserId];

      // Şu anki zaman
      final now = DateTime.now();

      // Tüm kullanıcıların hikayelerini al
      final storiesSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .where('userId', whereIn: userIds.isEmpty ? [''] : userIds)
          .where('expiresAt', isGreaterThan: now)
          .orderBy('expiresAt', descending: true)
          .get();

      // Hikayeleri kullanıcı ID'sine göre grupla
      final Map<String, List<StoryModel>> storiesByUser = {};

      for (var doc in storiesSnapshot.docs) {
        final story = StoryModel.fromSnapshot(doc);
        if (!storiesByUser.containsKey(story.userId)) {
          storiesByUser[story.userId] = [];
        }
        storiesByUser[story.userId]!.add(story);
      }

      // Her kullanıcının hikayelerini oluşturulma tarihine göre sırala
      storiesByUser.forEach((userId, stories) {
        stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

      if (mounted) {
        setState(() {
          _stories = storiesByUser;
          _isLoadingStories = false;
        });
      }
    } catch (e) {
      print('Hikayeler yüklenirken hata oluştu: $e');
      if (mounted) {
        setState(() {
          _isLoadingStories = false;
        });
      }
    }
  }

  void _loadPosts() {
    if (currentUserId == null) {
      setState(() {
        _isLoadingPosts = false;
      });
      return;
    }

    // Kullanıcının takip ettiği kişileri al
    FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .doc(currentUserId)
        .get()
        .then((userDoc) {
      if (!userDoc.exists) {
        setState(() {
          _isLoadingPosts = false;
        });
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final List<dynamic> following = userData['following'] ?? [];

      // Kullanıcının kendi ID'sini de ekle (kendi gönderilerini de görmesi için)
      final userIds = [...following, currentUserId];

      // Takip edilen kullanıcıların gönderilerini dinle
      _postsSubscription = FirebaseFirestore.instance
          .collection(AppConstants.postsCollection)
          .where('userId', whereIn: userIds.isEmpty ? [''] : userIds)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _posts = snapshot.docs;
            _isLoadingPosts = false;
          });
        }
      }, onError: (error) {
        print('Gönderiler yüklenirken hata oluştu: $error');
        if (mounted) {
          setState(() {
            _isLoadingPosts = false;
          });
        }
      });
    }).catchError((error) {
      print('Kullanıcı bilgileri alınırken hata oluştu: $error');
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    });
  }

  void _navigateToAddStory() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galeriden Resim Seç'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const AddStoryScreen(source: ImageSource.gallery),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Kamera ile Çek'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const AddStoryScreen(source: ImageSource.camera),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToMyStories() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MyStoriesScreen(),
      ),
    );
  }

  Future<void> _loadUsers() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final usersQuery = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .orderBy('username')
          .get();

      final List<Map<String, dynamic>> validUsers = [];

      for (var doc in usersQuery.docs) {
        final userData = doc.data();

        // Kullanıcının hala var olup olmadığını kontrol et
        try {
          final userRecord = await FirebaseAuth.instance
              .fetchSignInMethodsForEmail(userData['email']);
          if (userRecord.isNotEmpty) {
            validUsers.add({
              'id': doc.id,
              ...userData,
            });
          }
        } catch (e) {
          print('Kullanıcı kontrolü sırasında hata: $e');
          continue;
        }
      }

      setState(() {
        _users = validUsers;
      });
    } catch (e) {
      print('Kullanıcılar yüklenirken hata oluştu: $e');
      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Kullanıcılar yüklenirken bir hata oluştu',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InstaSon'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(AppConstants.notificationsCollection)
                    .where('recipientId', isEqualTo: currentUserId)
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox();
                  }

                  final unreadCount = snapshot.data!.docs.length;
                  return Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF800000),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStories();
          _loadPosts();
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Hikayeler
              Container(
                height: 100,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: _isLoadingStories
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // Kendi hikayeni ekle butonu
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: _navigateToAddStory,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      size: 30,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Hikaye Ekle',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),

                          // Kendi hikayelerini görüntüle butonu
                          if (_stories.containsKey(currentUserId) &&
                              _stories[currentUserId]!.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ViewStoryScreen(
                                            stories: _stories[currentUserId]!,
                                            userId: currentUserId!,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF800000),
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection(
                                                  AppConstants.usersCollection)
                                              .doc(currentUserId)
                                              .snapshots(),
                                          builder: (context, snapshot) {
                                            String profileImageUrl = '';
                                            if (snapshot.hasData &&
                                                snapshot.data!.exists) {
                                              final userData =
                                                  snapshot.data!.data()
                                                      as Map<String, dynamic>;
                                              profileImageUrl =
                                                  userData['profileImageUrl'] ??
                                                      '';
                                            }

                                            return CachedNetworkImage(
                                              imageUrl: profileImageUrl
                                                      .isNotEmpty
                                                  ? profileImageUrl
                                                  : _stories[currentUserId]![0]
                                                      .userProfileImageUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  const CircularProgressIndicator(),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(Icons.person),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Hikayem',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),

                          // Diğer kullanıcıların hikayeleri
                          ..._stories.entries
                              .where((entry) => entry.key != currentUserId)
                              .map((entry) {
                            final userId = entry.key;
                            final userStories = entry.value;
                            final firstStory = userStories.first;

                            // Kullanıcının hikayelerinden herhangi birini görüntülemiş mi?
                            final hasViewedAny = userStories.any((story) =>
                                story.viewedBy.contains(currentUserId));

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      // Tüm hikayeleri düz bir listede topluyoruz
                                      final allStories = _stories.values
                                          .expand((stories) => stories)
                                          .toList();

                                      // Tıklanan kullanıcının ilk hikayesinin indeksini buluyoruz
                                      final startIndex = allStories.indexWhere(
                                          (story) => story.userId == userId);

                                      if (startIndex != -1) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ViewStoryScreen(
                                              stories: allStories,
                                              userId: userId,
                                              initialStoryIndex: startIndex,
                                            ),
                                          ),
                                        ).then((_) => _loadStories());
                                      }
                                    },
                                    child: StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection(
                                              AppConstants.usersCollection)
                                          .doc(userId)
                                          .snapshots(),
                                      builder: (context, snapshot) {
                                        String profileImageUrl = '';
                                        if (snapshot.hasData &&
                                            snapshot.data!.exists) {
                                          final userData = snapshot.data!.data()
                                              as Map<String, dynamic>;
                                          profileImageUrl =
                                              userData['profileImageUrl'] ?? '';
                                        }

                                        return Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: hasViewedAny
                                                  ? Colors.grey
                                                  : const Color(0xFF800000),
                                              width: 2,
                                            ),
                                          ),
                                          child: ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  profileImageUrl.isNotEmpty
                                                      ? profileImageUrl
                                                      : firstStory
                                                          .userProfileImageUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  const CircularProgressIndicator(),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(Icons.person),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    firstStory.username,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
              ),

              // Gönderiler
              _isLoadingPosts
                  ? const Center(child: CircularProgressIndicator())
                  : _posts.isEmpty
                      ? const Center(
                          child: Text('Henüz gönderi yok'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post =
                                _posts[index].data() as Map<String, dynamic>;
                            final postId = _posts[index].id;

                            return PostCard(
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
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }
}
