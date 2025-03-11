import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<DocumentSnapshot> _users = [];
  List<DocumentSnapshot> _filteredUsers = [];
  List<String> _followingList = [];
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  Map<String, bool> _followingStatus = {};
  Map<String, bool> _loadingStatus = {};

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
    _getFollowingList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final usersSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .get();

      if (!mounted) return; // Widget hala ağaçta mı kontrol et
      
      setState(() {
        _users = usersSnapshot.docs;
        _filteredUsers = usersSnapshot.docs;
        _isLoading = false;
      });

      // Takip durumlarını kontrol et
      _checkFollowingStatus();
    } catch (e) {
      print('Kullanıcılar yüklenirken hata oluştu: $e');
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getFollowingList() async {
    if (currentUserId == null) {
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        
        if (!mounted) return;
        
        setState(() {
          _followingList = List<String>.from(userData['following'] ?? []);
        });
      }
    } catch (e) {
      print('Takip listesi yüklenirken hata oluştu: $e');
    }
  }

  Future<void> _checkFollowingStatus() async {
    if (currentUserId == null) return;

    try {
      final currentUserDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data() as Map<String, dynamic>;
        final List<dynamic> following = List<dynamic>.from(userData['following'] ?? []);

        setState(() {
          for (final user in _users) {
            final userId = user.id;
            if (userId != currentUserId) {
              _followingStatus[userId] = following.contains(userId);
              _loadingStatus[userId] = false;
            }
          }
        });
      }
    } catch (e) {
      print('Takip durumları kontrol edilirken hata oluştu: $e');
    }
  }

  void _searchUsers(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _users;
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();
    
    setState(() {
      _filteredUsers = _users.where((userDoc) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final username = (userData['username'] ?? '').toLowerCase();
        final fullName = (userData['fullName'] ?? '').toLowerCase();
        
        return username.contains(lowercaseQuery) || 
               fullName.contains(lowercaseQuery);
      }).toList();
    });
  }

  Future<void> _toggleFollow(String userId) async {
    if (currentUserId == null) return;

    setState(() {
      _loadingStatus[userId] = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      final userRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId);
      
      final currentUserRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId);
      
      // Güncel kullanıcı verilerini al
      final userDoc = await userRef.get();
      final currentUserDoc = await currentUserRef.get();
      
      if (!userDoc.exists || !currentUserDoc.exists) {
        throw Exception('Kullanıcı bulunamadı');
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;
      
      // Followers ve following listelerini al
      List<dynamic> followers = List<dynamic>.from(userData['followers'] ?? []);
      List<dynamic> following = List<dynamic>.from(currentUserData['following'] ?? []);
      
      final bool isFollowing = _followingStatus[userId] ?? false;
      
      if (isFollowing) {
        // Takibi bırak
        followers.remove(currentUserId);
        following.remove(userId);
        
        batch.update(userRef, {'followers': followers});
        batch.update(currentUserRef, {'following': following});
        
        // Bildirim varsa sil
        final notificationsQuery = await FirebaseFirestore.instance
            .collection(AppConstants.notificationsCollection)
            .where('type', isEqualTo: 'follow')
            .where('senderId', isEqualTo: currentUserId)
            .where('recipientId', isEqualTo: userId)
            .get();
        
        for (final doc in notificationsQuery.docs) {
          batch.delete(doc.reference);
        }
      } else {
        // Takip et
        followers.add(currentUserId);
        following.add(userId);
        
        batch.update(userRef, {'followers': followers});
        batch.update(currentUserRef, {'following': following});
        
        // Bildirim gönder
        batch.set(
          FirebaseFirestore.instance
              .collection(AppConstants.notificationsCollection)
              .doc(),
          {
            'type': 'follow',
            'senderId': currentUserId,
            'recipientId': userId,
            'createdAt': FieldValue.serverTimestamp(),
          }
        );
      }
      
      await batch.commit();
      
      setState(() {
        _followingStatus[userId] = !isFollowing;
        _loadingStatus[userId] = false;
      });
    } catch (e) {
      print('Takip işlemi sırasında hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Takip işlemi sırasında bir hata oluştu',
        type: SnackBarType.error,
      );
      
      setState(() {
        _loadingStatus[userId] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Kullanıcı ara...',
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onChanged: _searchUsers,
          ),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _filteredUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Kullanıcı bulunamadı',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final userData = _filteredUsers[index].data() as Map<String, dynamic>;
                    final userId = _filteredUsers[index].id;
                    
                    if (userId == currentUserId) {
                      return const SizedBox.shrink();
                    }
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: userData['profileImageUrl'] != null && 
                                          userData['profileImageUrl'].isNotEmpty
                              ? CachedNetworkImageProvider(userData['profileImageUrl'])
                              : null,
                          child: userData['profileImageUrl'] == null || 
                                 userData['profileImageUrl'].isEmpty
                              ? const Icon(Icons.person, size: 24)
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
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: userId != currentUserId
                            ? _loadingStatus[userId] == true
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: () => _toggleFollow(userId),
                                    style: TextButton.styleFrom(
                                      backgroundColor: _followingStatus[userId] == true
                                          ? Colors.grey[200]
                                          : const Color(0xFF800000),
                                      foregroundColor: _followingStatus[userId] == true
                                          ? Colors.black
                                          : Colors.white,
                                      minimumSize: const Size(80, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: Text(
                                      _followingStatus[userId] == true
                                          ? 'Takip Ediliyor'
                                          : 'Takip Et',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  )
                            : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(userId: userId),
                            ),
                          ).then((_) => _checkFollowingStatus());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
