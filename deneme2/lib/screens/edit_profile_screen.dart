import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  String? _currentProfileImageUrl;
  String? _initialUsername;
  dynamic _imageFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (currentUserId == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _fullNameController.text = userData['fullName'] ?? '';
          _usernameController.text = userData['username'] ?? '';
          _bioController.text = userData['bio'] ?? '';
          _currentProfileImageUrl = userData['profileImageUrl'];
          _initialUsername = userData['username'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Kullanıcı bilgileri yüklenirken hata oluştu: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = kIsWeb ? pickedFile : File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Resim seçilirken hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Resim seçilirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _currentProfileImageUrl;

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('$currentUserId.jpg');

      if (kIsWeb) {
        // Web için XFile kullanıyoruz
        await storageRef.putData(
          await _imageFile.readAsBytes(),
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        // Mobil için File kullanıyoruz
        await storageRef.putFile(_imageFile);
      }

      return await storageRef.getDownloadURL();
    } catch (e) {
      print('Resim yüklenirken hata oluştu: $e');
      throw Exception('Resim yüklenirken bir hata oluştu');
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profil Fotoğrafı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera ile Çek'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_currentProfileImageUrl != null && _currentProfileImageUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Profil Fotoğrafını Kaldır', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _currentProfileImageUrl = '';
                    _imageFile = null;
                  });
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        if (currentUserId == null) {
          throw Exception('Oturum açmanız gerekiyor');
        }

        // Kullanıcı belgesinin var olup olmadığını kontrol et
        final userDocRef = FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(currentUserId);
        
        final userDoc = await userDocRef.get();
        
        if (!userDoc.exists) {
          await userDocRef.set({
            'userId': currentUserId,
            'username': _usernameController.text.trim(),
            'fullName': _fullNameController.text.trim(),
            'bio': _bioController.text.trim(),
            'profileImageUrl': '',
            'followers': [],
            'following': [],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // Kullanıcı adının benzersiz olup olmadığını kontrol et
        if (_usernameController.text != _initialUsername) {
          final usernameQuery = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .where('username', isEqualTo: _usernameController.text.trim())
              .get();
          
          if (usernameQuery.docs.isNotEmpty && 
              usernameQuery.docs.first.id != currentUserId) {
            throw Exception('Bu kullanıcı adı zaten kullanılıyor');
          }
        }

        // Profil fotoğrafını güncelle
        String profileImageUrl = _currentProfileImageUrl ?? '';
        
        if (_imageFile != null) {
          profileImageUrl = await _uploadImage() ?? '';
        }

        // Kullanıcı bilgilerini güncelle
        await userDocRef.update({
          'fullName': _fullNameController.text.trim(),
          'username': _usernameController.text.trim(),
          'bio': _bioController.text.trim(),
          'profileImageUrl': profileImageUrl,
        });
        
        // Kullanıcının gönderilerindeki profil fotoğrafı URL'sini güncelle
        final batch = FirebaseFirestore.instance.batch();
        final postsQuery = await FirebaseFirestore.instance
            .collection(AppConstants.postsCollection)
            .where('userId', isEqualTo: currentUserId)
            .get();
        
        for (final postDoc in postsQuery.docs) {
          batch.update(postDoc.reference, {
            'userProfileImageUrl': profileImageUrl,
            'username': _usernameController.text.trim(),
          });
        }
        
        await batch.commit();
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: 'Profil güncellendi',
          type: SnackBarType.success,
        );
        
        Navigator.pop(context);
      } catch (e) {
        print('Profil güncellenirken hata oluştu: $e');
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: 'Profil güncellenirken bir hata oluştu: $e',
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _updateProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profil fotoğrafı
                    GestureDetector(
                      onTap: _showImageSourceDialog,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _imageFile != null
                                ? (kIsWeb
                                    ? NetworkImage(_imageFile.path)
                                    : FileImage(_imageFile) as ImageProvider)
                                : _currentProfileImageUrl != null && _currentProfileImageUrl!.isNotEmpty
                                    ? CachedNetworkImageProvider(_currentProfileImageUrl!)
                                    : null,
                            child: _imageFile == null && 
                                  (_currentProfileImageUrl == null || _currentProfileImageUrl!.isEmpty)
                                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Tam ad
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tam Ad',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Tam adınızı girin';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Kullanıcı adı
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı Adı',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Kullanıcı adınızı girin';
                        }
                        if (value.contains(' ')) {
                          return 'Kullanıcı adı boşluk içeremez';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Biyografi
                    TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'Biyografi',
                        prefixIcon: Icon(Icons.info),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    
                    // Güncelle butonu
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _updateProfile,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Profili Güncelle'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
} 