import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'chat_detail_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({Key? key}) : super(key: key);

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final _searchController = TextEditingController();
  List<String> _followingIds = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final List<dynamic> following = userData['following'] ?? [];
        
        setState(() {
          _followingIds = following.map((id) => id.toString()).toList();
        });
        
        await _loadFollowingUsers();
      }
    } catch (e) {
      print('Takip edilenler yüklenirken hata: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadFollowingUsers() async {
    final users = <Map<String, dynamic>>[];
    
    for (final userId in _followingIds) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(userId)
            .get();
            
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          // Kullanıcının sizi takip ettiğini kontrol et (karşılıklı takipleşme)
          final followers = List<String>.from(userData['followers'] ?? []);
          if (followers.contains(currentUserId)) {
            users.add({
              'id': userId,
              'username': userData['username'] ?? 'Kullanıcı',
              'fullName': userData['fullName'] ?? '',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
              'isMutual': true,
            });
          } else {
            users.add({
              'id': userId,
              'username': userData['username'] ?? 'Kullanıcı',
              'fullName': userData['fullName'] ?? '',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
              'isMutual': false,
            });
          }
        }
      } catch (e) {
        print('Kullanıcı bilgileri yüklenirken hata: $e');
      }
    }
    
    setState(() {
      _allUsers = users;
      _filteredUsers = users;
    });
  }
  
  void _filterUsers(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
    });
    
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _allUsers;
      });
      return;
    }
    
    final lowercaseQuery = query.toLowerCase();
    
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final username = (user['username'] ?? '').toLowerCase();
        final fullName = (user['fullName'] ?? '').toLowerCase();
        return username.contains(lowercaseQuery) || fullName.contains(lowercaseQuery);
      }).toList();
    });
  }
  
  Future<void> _checkExistingChat(String receiverId, String receiverName, String receiverProfileImageUrl) async {
    try {
      // Mevcut sohbeti kontrol et
      final querySnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.chatsCollection)
          .where('participants', arrayContains: currentUserId)
          .get();
          
      for (final doc in querySnapshot.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(receiverId)) {
          // Mevcut sohbeti bulduk
          if (!mounted) return;
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(
                chatId: doc.id,
                receiverId: receiverId,
                receiverName: receiverName,
                receiverProfileImageUrl: receiverProfileImageUrl,
              ),
            ),
          );
          return;
        }
      }
      
      // Mevcut sohbet yoksa yeni sohbet oluştur
      final newChatRef = await FirebaseFirestore.instance
          .collection(AppConstants.chatsCollection)
          .add({
            'participants': [currentUserId, receiverId],
            'lastMessage': '',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessageSenderId': currentUserId,
            'unreadCount': {
              currentUserId: 0,
              receiverId: 0,
            },
            'createdAt': FieldValue.serverTimestamp(),
          });
          
      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chatId: newChatRef.id,
            receiverId: receiverId,
            receiverName: receiverName,
            receiverProfileImageUrl: receiverProfileImageUrl,
          ),
        ),
      );
    } catch (e) {
      print('Sohbet kontrol edilirken hata: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Sohbet başlatılırken bir hata oluştu',
          type: SnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sohbet'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
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
                onChanged: _filterUsers,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSearching ? Icons.search_off : Icons.people_outline,
                        size: 80,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isSearching
                            ? 'Arama sonucu bulunamadı'
                            : 'Henüz takip ettiğiniz kimse yok',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredUsers[index];
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['profileImageUrl'] != null && 
                                        user['profileImageUrl'].isNotEmpty
                            ? CachedNetworkImageProvider(user['profileImageUrl'])
                            : null,
                        child: user['profileImageUrl'] == null || 
                               user['profileImageUrl'].isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        user['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(user['fullName'] ?? ''),
                      trailing: user['isMutual']
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            )
                          : const Icon(
                              Icons.info_outline,
                              color: Colors.grey,
                            ),
                      onTap: () {
                        if (user['isMutual']) {
                          _checkExistingChat(
                            user['id'],
                            user['username'],
                            user['profileImageUrl'],
                          );
                        } else {
                          CustomSnackBar.show(
                            context: context,
                            message: 'Bu kullanıcı ile mesajlaşabilmek için karşılıklı takipleşmeniz gerekiyor',
                            type: SnackBarType.warning,
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }
} 