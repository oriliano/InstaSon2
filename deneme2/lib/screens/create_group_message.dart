import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Set<String> _selectedUsers = {};
  bool _isLoading = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Önce takipçileri al
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final List<dynamic> followers = userData['followers'] ?? [];
        final List<dynamic> following = userData['following'] ?? [];

        // Karşılıklı takipleşenleri bul
        final mutualUsers =
            followers.where((id) => following.contains(id)).toList();

        final users = <Map<String, dynamic>>[];

        // Karşılıklı takipleşilen kullanıcıların bilgilerini al
        for (final userId in mutualUsers) {
          final userDoc = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(userId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            users.add({
              'id': userId,
              'username': userData['username'] ?? 'Kullanıcı',
              'fullName': userData['fullName'] ?? '',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
            });
          }
        }

        setState(() {
          _allUsers = users;
          _filteredUsers = users;
        });
      }
    } catch (e) {
      print('Kullanıcılar yüklenirken hata: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterUsers(String query) {
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
        return username.contains(lowercaseQuery) ||
            fullName.contains(lowercaseQuery);
      }).toList();
    });
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Resim seçilirken hata: $e');
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      CustomSnackBar.show(
        context: context,
        message: 'Lütfen bir grup adı girin',
        type: SnackBarType.error,
      );
      return;
    }

    if (_selectedUsers.isEmpty) {
      CustomSnackBar.show(
        context: context,
        message: 'Lütfen en az bir kullanıcı seçin',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? groupImageUrl;

      // Grup fotoğrafını yükle
      if (_selectedImage != null) {
        final fileName = 'group_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance
            .ref()
            .child('group_images')
            .child(fileName);

        await ref.putFile(_selectedImage!);
        groupImageUrl = await ref.getDownloadURL();
      }

      // Grup üyelerini hazırla (kendini de ekle)
      final members = [..._selectedUsers, currentUserId!];

      // Grubu oluştur
      final groupRef =
          await FirebaseFirestore.instance.collection('groups').add({
        'name': _groupNameController.text.trim(),
        'imageUrl': groupImageUrl,
        'createdBy': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'members': members,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'unreadCount':
            Map.fromIterable(members, key: (e) => e, value: (e) => 0),
      });

      // Grup sohbetini oluştur
      await FirebaseFirestore.instance.collection('chats').add({
        'participants': members,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageSenderId': '',
        'unreadCount':
            Map.fromIterable(members, key: (e) => e, value: (e) => 0),
        'isGroup': true,
        'groupId': groupRef.id,
        'groupName': _groupNameController.text.trim(),
        'groupImageUrl': groupImageUrl,
      });

      if (!mounted) return;

      // Ana sayfaya dön
      Navigator.pop(context);

      CustomSnackBar.show(
        context: context,
        message: 'Grup başarıyla oluşturuldu',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Grup oluşturulurken hata: $e');
      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Grup oluşturulurken bir hata oluştu',
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
        title: const Text('Yeni Grup Oluştur'),
        actions: [
          if (_selectedUsers.isNotEmpty)
            TextButton(
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Oluştur',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Grup bilgileri
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: _selectedImage != null
                        ? ClipOval(
                            child: Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            size: 30,
                            color: Colors.grey,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      hintText: 'Grup adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Seçili kullanıcılar
          if (_selectedUsers.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedUsers.length,
                itemBuilder: (context, index) {
                  final userId = _selectedUsers.elementAt(index);
                  final user = _allUsers.firstWhere((u) => u['id'] == userId);

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundImage:
                                  user['profileImageUrl'] != null &&
                                          user['profileImageUrl'].isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          user['profileImageUrl'])
                                      : null,
                              child: user['profileImageUrl'] == null ||
                                      user['profileImageUrl'].isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            Positioned(
                              right: -5,
                              top: -5,
                              child: IconButton(
                                icon: const Icon(Icons.cancel,
                                    color: Colors.red, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _selectedUsers.remove(userId);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user['username'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Arama alanı
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kullanıcı ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onChanged: _filterUsers,
            ),
          ),

          // Kullanıcı listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? const Center(child: Text('Kullanıcı bulunamadı'))
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final isSelected =
                              _selectedUsers.contains(user['id']);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  user['profileImageUrl'] != null &&
                                          user['profileImageUrl'].isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          user['profileImageUrl'])
                                      : null,
                              child: user['profileImageUrl'] == null ||
                                      user['profileImageUrl'].isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(user['username']),
                            subtitle: Text(user['fullName']),
                            trailing: IconButton(
                              icon: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: isSelected ? Colors.green : Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedUsers.remove(user['id']);
                                  } else {
                                    _selectedUsers.add(user['id']);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
