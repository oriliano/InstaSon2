import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;

class AddPostScreen extends StatefulWidget {
  final ImageSource source;

  const AddPostScreen({
    Key? key,
    required this.source,
  }) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  File? _selectedImage;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getImage(widget.source);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      } else {
        // Kullanıcı seçim yapmadı, geri git
        if (!mounted) return;
        Navigator.pop(context);
      }
    } catch (e) {
      print('Fotoğraf seçilirken hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Fotoğraf seçilirken bir hata oluştu',
        type: SnackBarType.error,
      );
      
      Navigator.pop(context);
    }
  }

  Future<void> _sharePost() async {
    if (currentUserId == null) {
      CustomSnackBar.show(
        context: context,
        message: 'Oturum açmanız gerekiyor',
        type: SnackBarType.error,
      );
      return;
    }

    if (_selectedImage == null) {
      CustomSnackBar.show(
        context: context,
        message: 'Lütfen bir görsel seçin',
        type: SnackBarType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Kullanıcı bilgilerini al
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .get();
      
      if (!userDoc.exists) {
        throw Exception('Kullanıcı bulunamadı');
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      
      // Firebase Storage'a görseli yükle
      final fileName = '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}${path.extension(_selectedImage!.path)}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('posts')
          .child(fileName);
      
      final uploadTask = storageRef.putFile(_selectedImage!);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Firestore'a gönderi ekle
      await FirebaseFirestore.instance.collection(AppConstants.postsCollection).add({
        'userId': currentUserId,
        'username': userData['username'] ?? '',
        'userProfileImageUrl': userData['profileImageUrl'] ?? '',
        'mediaUrl': downloadUrl,
        'isVideo': false,
        'caption': _captionController.text.trim(),
        'location': _locationController.text.trim(),
        'likes': [],
        'comments': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Gönderi başarıyla paylaşıldı',
        type: SnackBarType.success,
      );
      
      Navigator.pop(context);
    } catch (e) {
      print('Gönderi paylaşılırken hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Gönderi paylaşılırken bir hata oluştu',
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
        title: const Text('Yeni Gönderi'),
        actions: [
          if (_selectedImage != null)
            TextButton(
              onPressed: _isLoading ? null : _sharePost,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Paylaş',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
        ],
      ),
      body: _selectedImage == null
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Seçilen görsel
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: Colors.black,
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Açıklama
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      controller: _captionController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        hintText: 'Bu gönderi hakkında bir şeyler yaz...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Konum
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Konum',
                        hintText: 'Konum ekle',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Medyayı değiştir butonu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: OutlinedButton.icon(
                      onPressed: () => _getImage(ImageSource.gallery),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Medyayı Değiştir'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
} 