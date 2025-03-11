import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/story_model.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'profile_screen.dart';

class ViewStoryScreen extends StatefulWidget {
  final List<StoryModel> stories;
  final String userId;
  final int initialStoryIndex;

  const ViewStoryScreen({
    Key? key,
    required this.stories,
    required this.userId,
    this.initialStoryIndex = 0,
  }) : super(key: key);

  @override
  State<ViewStoryScreen> createState() => _ViewStoryScreenState();
}

class _ViewStoryScreenState extends State<ViewStoryScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  VideoPlayerController? _videoPlayerController;
  late int _currentIndex;
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool _isCurrentUserStory = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(vsync: this);
    _isCurrentUserStory = widget.userId == currentUserId;
    _currentIndex = widget.initialStoryIndex;

    _loadStory(_currentIndex);

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.stop();
        _animationController.reset();
        setState(() {
          if (_currentIndex + 1 < widget.stories.length) {
            _currentIndex += 1;
            _loadStory(_currentIndex);
          } else {
            // Son hikayeden sonra geri dön
            Navigator.pop(context);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  void _loadStory(int index) {
    _animationController.stop();
    _animationController.reset();

    if (_videoPlayerController != null) {
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }

    if (widget.stories[index].isVideo) {
      _videoPlayerController =
          VideoPlayerController.network(widget.stories[index].mediaUrl)
            ..initialize().then((_) {
              setState(() {});
              if (_videoPlayerController!.value.isInitialized) {
                _animationController.duration =
                    _videoPlayerController!.value.duration;
                _videoPlayerController!.play();
                _animationController.forward();
              }
            });
    } else {
      _animationController.duration = const Duration(seconds: 5);
      _animationController.forward();
    }

    // Hikaye görüntülendi olarak işaretle
    if (currentUserId != widget.userId) {
      _markStoryAsViewed(widget.stories[index].storyId);
    }
  }

  void _markStoryAsViewed(String storyId) async {
    try {
      final storyDoc = await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .doc(storyId)
          .get();

      if (storyDoc.exists) {
        final storyData = storyDoc.data() as Map<String, dynamic>;
        List<String> viewedBy = storyData['viewedBy'] != null
            ? List<String>.from(storyData['viewedBy'])
            : [];

        if (!viewedBy.contains(currentUserId)) {
          viewedBy.add(currentUserId);
          await FirebaseFirestore.instance
              .collection(AppConstants.storiesCollection)
              .doc(storyId)
              .update({'viewedBy': viewedBy});

          // Hikaye sahibinin bildirimler koleksiyonuna bildirim ekle
          if (storyData['userId'] != currentUserId) {
            // Geçerli kullanıcı bilgilerini al
            final userDoc = await FirebaseFirestore.instance
                .collection(AppConstants.usersCollection)
                .doc(currentUserId)
                .get();

            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;

              await FirebaseFirestore.instance
                  .collection(AppConstants.notificationsCollection)
                  .add({
                'type': 'story_view',
                'senderId': currentUserId,
                'senderUsername': userData['username'],
                'senderProfileImageUrl': userData['profileImageUrl'],
                'recipientId': storyData['userId'],
                'storyId': storyId,
                'createdAt': FieldValue.serverTimestamp(),
                'isRead': false,
              });
            }
          }
        }
      }
    } catch (e) {
      print('Hikaye görüntülenme durumu güncellenirken hata oluştu: $e');
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;

    if (dx < screenWidth / 3) {
      // Sol tarafına tıklandı - önceki hikaye
      setState(() {
        if (_currentIndex - 1 >= 0) {
          _currentIndex -= 1;
          _loadStory(_currentIndex);
        } else {
          // İlk hikayeden öncesine gitmek istiyorsa geri dön
          Navigator.pop(context);
        }
      });
    } else if (dx > 2 * screenWidth / 3) {
      // Sağ tarafına tıklandı - sonraki hikaye
      setState(() {
        if (_currentIndex + 1 < widget.stories.length) {
          _currentIndex += 1;
          _loadStory(_currentIndex);
        } else {
          // Son hikayeden sonra geri dön
          Navigator.pop(context);
        }
      });
    }
  }

  void _deleteStory(String storyId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hikayeyi Sil'),
        content: const Text('Bu hikayeyi silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performStoryDeletion(storyId);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performStoryDeletion(String storyId) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .doc(storyId)
          .delete();

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Hikaye başarıyla silindi',
        type: SnackBarType.success,
      );

      // Eğer bu son hikaye ise ekranı kapat
      if (widget.stories.length <= 1) {
        Navigator.pop(context);
      } else {
        // Değilse bir sonraki hikayeye geçiş yap
        setState(() {
          widget.stories.removeWhere((story) => story.storyId == storyId);
          if (_currentIndex >= widget.stories.length) {
            _currentIndex = widget.stories.length - 1;
          }
          _loadStory(_currentIndex);
        });
      }
    } catch (e) {
      print('Hikaye silinirken hata oluştu: $e');
      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Hikaye silinirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: widget.userId),
      ),
    ).then((_) {
      // Profil sayfasından döndüğümüzde hikayeleri yeniden yükle
      if (mounted) {
        _loadStory(_currentIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentStory =
        widget.stories.isNotEmpty ? widget.stories[_currentIndex] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: currentStory == null
          ? const Center(
              child: Text('Hikaye bulunamadı',
                  style: TextStyle(color: Colors.white)))
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection(AppConstants.usersCollection)
                  .doc(currentStory.userId)
                  .get(),
              builder: (context, snapshot) {
                // Kullanıcı bilgilerini gerçek zamanlı olarak al
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final username = userData?['username'] ?? currentStory.username;
                final profileImageUrl = userData?['profileImageUrl'] ??
                    currentStory.userProfileImageUrl;

                return GestureDetector(
                  onTapDown: (details) => _onTapDown(details),
                  child: Stack(
                    children: [
                      // Story içeriği
                      Positioned.fill(
                        child: currentStory.isVideo &&
                                _videoPlayerController != null
                            ? Container(
                                color: Colors.black,
                                child:
                                    _videoPlayerController!.value.isInitialized
                                        ? AspectRatio(
                                            aspectRatio: _videoPlayerController!
                                                .value.aspectRatio,
                                            child: VideoPlayer(
                                                _videoPlayerController!),
                                          )
                                        : const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                              )
                            : Container(
                                color: Colors.black,
                                child: CachedNetworkImage(
                                  imageUrl: currentStory.mediaUrl,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Center(
                                    child: Icon(
                                      Icons.error,
                                      color: Colors.white,
                                      size: 50,
                                    ),
                                  ),
                                ),
                              ),
                      ),

                      // Üst bilgi çubuğu
                      Positioned(
                        top: MediaQuery.of(context).padding.top,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 8.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundImage: profileImageUrl.isNotEmpty
                                    ? CachedNetworkImageProvider(
                                        profileImageUrl)
                                    : null,
                                child: profileImageUrl.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _navigateToProfile,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        username,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        timeago.format(currentStory.createdAt,
                                            locale: 'tr'),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Görüntüleyenleri gösterme butonu
                              if (currentStory.userId == currentUserId &&
                                  currentStory.viewedBy.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: InkWell(
                                    onTap: () => _showViewers(currentStory),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        borderRadius:
                                            BorderRadius.circular(16.0),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.remove_red_eye,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            (currentStory.viewedBy.length - 1)
                                                .toString(),
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              // Seçenekler menüsü (sadece kendi hikayemiz için)
                              if (currentStory.userId == currentUserId)
                                IconButton(
                                  icon: const Icon(Icons.more_vert,
                                      color: Colors.white),
                                  onPressed: () =>
                                      _showStoryOptions(currentStory),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // İlerleme çubuğu
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          children: List.generate(
                            widget.stories.length,
                            (index) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: LinearProgressIndicator(
                                  value: index == _currentIndex
                                      ? _animationController.value
                                      : index < _currentIndex
                                          ? 1
                                          : 0,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.3),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    index < _currentIndex ||
                                            (index == _currentIndex &&
                                                currentStory.viewedBy
                                                    .contains(currentUserId))
                                        ? Colors.white
                                        : const Color(0xFF800000), // Bordo
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showViewers(StoryModel story) {
    // Öncelikle duplicate'leri kaldırıyoruz:
    final uniqueViewers = Set<String>.from(story.viewedBy);
    // Hem hikaye sahibini hem de mevcut kullanıcıyı filtreleyelim:
    final filteredViewers = uniqueViewers
        .where((id) =>
            id != story.userId && id != FirebaseAuth.instance.currentUser!.uid)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Görüntüleyenler (${filteredViewers.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: filteredViewers.isEmpty
                    ? const Center(child: Text('Henüz kimse görüntülemedi'))
                    : FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection(AppConstants.usersCollection)
                            .where(FieldPath.documentId, whereIn: filteredViewers)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Bir hata oluştu: ${snapshot.error}'),
                            );
                          }

                          final viewers = snapshot.data?.docs ?? [];

                          return ListView.builder(
                            itemCount: viewers.length,
                            itemBuilder: (context, index) {
                              final viewerData = viewers[index].data() as Map<String, dynamic>;
                              final viewerId = viewers[index].id;
                              final username = viewerData['username'] ?? 'Kullanıcı';
                              final profileImageUrl = viewerData['profileImageUrl'] ?? '';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: profileImageUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(profileImageUrl)
                                      : null,
                                  child: profileImageUrl.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                title: Text(username),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ProfileScreen(userId: viewerId),
                                    ),
                                  ).then((_) {
                                    // Profil sayfasından döndüğümüzde hikayeleri yeniden yükle
                                    if (mounted) {
                                      _loadStory(_currentIndex);
                                    }
                                  });
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
  }

  void _showStoryOptions(StoryModel story) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                title: const Text('Hikayeyi Sil',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteStory(story.storyId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_red_eye),
                title: const Text('Görüntüleyenler'),
                onTap: () {
                  Navigator.pop(context);
                  _showViewers(story);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('İptal'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
