import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/story_model.dart';
import '../utils/constants.dart';
import 'profile_screen.dart';
import 'view_story_screen.dart';

class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({Key? key}) : super(key: key);

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  List<StoryModel> _myStories = [];
  bool _isLoading = true;
  // Hikayeyi görüntüleyenlerin profili
  Map<String, Map<String, dynamic>> _viewerProfiles = {};

  @override
  void initState() {
    super.initState();
    _loadMyStories();
  }

  Future<void> _loadMyStories() async {
    if (currentUserId == null) return;

    setState(() => _isLoading = true);

    try {
      final storiesQuery = await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .where('userId', isEqualTo: currentUserId)
          .orderBy('createdAt', descending: true)
          .get();

      final stories =
          storiesQuery.docs.map((doc) => StoryModel.fromSnapshot(doc)).toList();

      setState(() {
        _myStories = stories;
      });

      // Görüntüleyenlerin profillerini yükle
      await _loadViewerProfiles();
    } catch (e) {
      print('Hikayeler yüklenirken hata oluştu: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadViewerProfiles() async {
    final viewerIds = <String>{};
    final validViewerIds = <String>{};

    // Tüm görüntüleyenlerin ID'lerini topla
    for (final story in _myStories) {
      for (final viewerId in story.viewedBy) {
        viewerIds.add(viewerId);
      }
    }

    // Görüntüleyenlerin profillerini Firestore'dan çek
    for (final viewerId in viewerIds) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(viewerId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          _viewerProfiles[viewerId] = {
            'username': userData['username'] ?? 'Kullanıcı',
            'profileImageUrl': userData['profileImageUrl'] ?? '',
            'fullName': userData['fullName'] ?? '',
          };
          validViewerIds.add(viewerId);
        }
      } catch (e) {
        print('Kullanıcı profili yüklenirken hata oluştu: $e');
      }
    }

    // Geçersiz kullanıcıları hikayelerden kaldır
    for (final story in _myStories) {
      story.viewedBy.removeWhere((id) => !validViewerIds.contains(id));
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteStory(String storyId) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.storiesCollection)
          .doc(storyId)
          .delete();

      setState(() {
        _myStories.removeWhere((s) => s.storyId == storyId);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hikaye başarıyla silindi')),
      );
    } catch (e) {
      print('Hikaye silinirken hata oluştu: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hikaye silinirken bir hata oluştu')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hikayelerim'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myStories.isEmpty
              ? const Center(child: Text('Henüz hikayen yok'))
              : ListView.builder(
                  itemCount: _myStories.length,
                  itemBuilder: (context, index) {
                    final story = _myStories[index];
                    final viewCount = story.viewedBy.length;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Story önizleme
                          GestureDetector(
                            onTap: () {
                              // Tek hikayeyi listeye dönüştürüp gönderiyoruz
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ViewStoryScreen(
                                    userId: currentUserId!,
                                    stories: [story],
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                image: story.isVideo
                                    ? null
                                    : DecorationImage(
                                        image: CachedNetworkImageProvider(
                                          story.mediaUrl,
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              child: story.isVideo
                                  ? const Center(
                                      child: Icon(
                                        Icons.play_circle_outline,
                                        color: Colors.white,
                                        size: 50,
                                      ),
                                    )
                                  : null,
                            ),
                          ),

                          // Alt bilgi (tarih, görüntüleme sayısı, silme ikonu)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Text(
                                  timeago.format(
                                    story.createdAt,
                                    locale: 'tr',
                                  ),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const Spacer(),
                                // Görüntülenme sayısı için özel bir buton ekle
                                ElevatedButton.icon(
                                  onPressed: () {
                                    _showViewersDialog(context, story);
                                  },
                                  icon: const Icon(Icons.visibility),
                                  label: Text('$viewCount görüntüleme'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF800000), // Bordo renk
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deleteStory(story.storyId),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  // Görüntüleyenleri göstermek için dialog
  void _showViewersDialog(BuildContext context, StoryModel story) {
    // Duplicate'leri kaldırıp, hem hikaye sahibini hem de (opsiyonel olarak) mevcut kullanıcıyı filtreleyelim.
    final filteredViewers = Set<String>.from(story.viewedBy)
        .where((id) =>
            id != story.userId && id != FirebaseAuth.instance.currentUser!.uid)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
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
                    : ListView.builder(
                        itemCount: filteredViewers.length,
                        itemBuilder: (context, viewerIndex) {
                          final viewerId = filteredViewers[viewerIndex];
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection(AppConstants.usersCollection)
                                .doc(viewerId)
                                .get(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const ListTile(
                                  leading: CircleAvatar(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  title: Text('Yükleniyor...'),
                                );
                              }
                              if (snapshot.hasError ||
                                  !snapshot.hasData ||
                                  !snapshot.data!.exists) {
                                // Belge bulunamazsa, boş widget döndür.
                                return const SizedBox.shrink();
                              }
                              final userData =
                                  snapshot.data!.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage:
                                      userData['profileImageUrl'] != null &&
                                              userData['profileImageUrl']
                                                  .isNotEmpty
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
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(userData['fullName'] ?? ''),
                                trailing: const Text(
                                  'Görüntüledi',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ProfileScreen(userId: viewerId),
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
  }
}
