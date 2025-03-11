import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';

class AddStoryScreen extends StatefulWidget {
  final ImageSource? source;

  const AddStoryScreen({
    Key? key,
    this.source,
  }) : super(key: key);

  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  dynamic _selectedImage;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.source != null) {
      _getImage(widget.source!);
    }
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = kIsWeb ? pickedFile : File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Fotoğraf seçilirken hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Fotoğraf seçilirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<void> _shareStory() async {
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
      final fileName = '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}${path.extension(_selectedImage.path)}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('stories')
          .child(fileName);
      
      UploadTask uploadTask;
      if (kIsWeb) {
        // Web için XFile kullanıyoruz
        uploadTask = storageRef.putData(
          await _selectedImage.readAsBytes(),
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        // Mobil için File kullanıyoruz
        uploadTask = storageRef.putFile(_selectedImage);
      }
      
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Hikaye sona erme tarihini hesapla (24 saat sonra)
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));
      
      // Firestore'a hikaye ekle
      await FirebaseFirestore.instance.collection(AppConstants.storiesCollection).add({
        'userId': currentUserId,
        'username': userData['username'] ?? '',
        'userProfileImageUrl': userData['profileImageUrl'] ?? '',
        'mediaUrl': downloadUrl,
        'isVideo': false,
        'createdAt': now,
        'expiresAt': expiresAt,
        'viewedBy': [],
      });
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Hikaye başarıyla paylaşıldı',
        type: SnackBarType.success,
      );
      
      Navigator.pop(context);
    } catch (e) {
      print('Hikaye paylaşılırken hata oluştu: $e');
      
      if (!mounted) return;
      
      CustomSnackBar.show(
        context: context,
        message: 'Hikaye paylaşılırken bir hata oluştu',
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
        title: const Text('Hikaye Ekle'),
        actions: [
          if (_selectedImage != null)
            TextButton(
              onPressed: _isLoading ? null : _shareStory,
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
                      ),
                    ),
            ),
        ],
      ),
      body: _selectedImage == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Hikaye Ekle',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _getImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeriden Resim Seç'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _getImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Kamera ile Çek'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Seçilen görsel
                kIsWeb
                    ? Image.network(
                        _selectedImage.path,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                      )
                    : Image.file(
                        _selectedImage,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                      ),
                // Görseli değiştirme butonu
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: () => _getImage(ImageSource.gallery),
                    child: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
    );
  }
}