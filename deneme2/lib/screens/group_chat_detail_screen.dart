import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/public/flutter_sound_recorder.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/models/audioController.dart';
import 'package:instason/screens/profile_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/messagebubble.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? groupImageUrl;
  final String chatId;

  const GroupChatDetailScreen({
    Key? key,
    required this.groupId,
    required this.groupName,
    this.groupImageUrl,
    required this.chatId,
  }) : super(key: key);

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioController audioController = Get.put(AudioController());
  bool _isLoading = false;
  bool _isSending = false;
  bool _isAdmin = false;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  /// Grup üyelerini statik olarak tutuyoruz;
  /// Eğer canlı takip istiyorsanız StreamBuilder tercih edin.
  List<Map<String, dynamic>> _groupMembers = [];

  /// SES KAYDI İÇİN
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
    _markMessagesAsRead();
    _initRecorder();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();

    /// Kaydediciyi kapat (ses kaydı oturumunu sonlandır)
    _recorder.closeRecorder();
    super.dispose();
  }

  //------------------------------------------------------------------------
  // SES KAYDI KURULUMU
  //------------------------------------------------------------------------
  Future<void> _initRecorder() async {
    /// Mikrofon izni
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      print('Mikrofon izni reddedildi!');
      return;
    }

    /// Kaydediciyi aç
    await _recorder.openRecorder();
    _isRecorderInitialized = true;
  }

  /// Kaydı başlat
  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) return;
    setState(() => _isRecording = true);

    await _recorder.startRecorder(
      toFile: 'temp_voice.aac',
      // codec: Codec.aacADTS, // opsiyonel
    );
  }

  /// Kaydı durdur
  Future<String?> _stopRecording() async {
    if (!_isRecorderInitialized) return null;
    setState(() => _isRecording = false);

    /// Bize kaydedilen dosya yolunu döndürür (örn: /data/user/0/...temp_voice.aac)
    return await _recorder.stopRecorder();
  }

  /// Durdurduğumuz kaydı Firebase'e yükle ve mesaj at
  Future<void> _uploadVoiceAndSend(String filePath) async {
    final fileName =
        'voice_${currentUserId}_${DateTime.now().millisecondsSinceEpoch}.aac';

    final ref = FirebaseStorage.instance
        .ref()
        .child('group_voice_messages')
        .child(fileName);

    // Dosyayı yükle
    await ref.putFile(File(filePath));
    final voiceUrl = await ref.getDownloadURL();

    // Diğer mesaj alanlarına benzer şekilde 'voiceUrl' ile groupchat'e ekleyelim
    final currentUser = _groupMembers.firstWhere(
      (member) => member['id'] == currentUserId,
      orElse: () => {
        'id': currentUserId,
        'username': 'Bilinmeyen Kullanıcı',
        'profileImageUrl': '',
      },
    );

    await FirebaseFirestore.instance.collection('groupchat').add({
      'chatId': widget.chatId,
      'groupId': widget.groupId,
      'senderId': currentUserId,
      'senderUsername': currentUser['username'],
      'senderProfileImageUrl': currentUser['profileImageUrl'],
      'content': '', // metin yok
      'voiceUrl': voiceUrl, // Ses dosyası
      'timestamp': FieldValue.serverTimestamp(),
      'imageUrl': null,
      'isRead': false,
    });

    // unreadCount vb. (gruptaki herkese +1)
    final unreadUpdates = <String, dynamic>{};
    for (final member in _groupMembers) {
      final memberId = member['id'] as String?;
      if (memberId != null && memberId != currentUserId) {
        unreadUpdates['unreadCount.$memberId'] = FieldValue.increment(1);
      }
    }

    // Grup belgesi
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({
      'lastMessage': 'Sesli mesaj gönderildi',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUserId,
      'lastMessageSenderUsername': currentUser['username'],
      ...unreadUpdates,
    });

    // Chats belgesi
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .update({
      'lastMessage': 'Sesli mesaj gönderildi',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUserId,
      'lastMessageSenderUsername': currentUser['username'],
      ...unreadUpdates,
    });
  }

  //------------------------------------------------------------------------
  // MESAJ SİL / DÜZENLE
  //------------------------------------------------------------------------
  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('groupchat')
          .doc(messageId)
          .delete();

      CustomSnackBar.show(
        context: context,
        message: 'Mesaj silindi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Mesaj silinirken hata: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Mesaj silinirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<void> _editMessage(String messageId, String newContent) async {
    try {
      await FirebaseFirestore.instance
          .collection('groupchat')
          .doc(messageId)
          .update({'content': newContent});

      CustomSnackBar.show(
        context: context,
        message: 'Mesaj güncellendi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Mesaj düzenlenirken hata: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Mesaj düzenlenirken bir hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  void _showEditMessageDialog(String messageId, String currentContent) {
    final controller = TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı Düzenle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context);
                await _editMessage(messageId, newContent);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  //------------------------------------------------------------------------
  // GRUP BİLGİSİ YÜKLEME
  //------------------------------------------------------------------------
  Future<void> _loadGroupInfo() async {
    setState(() => _isLoading = true);

    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        final groupData = groupDoc.data() as Map<String, dynamic>;
        final memberIds = groupData['members'] ?? [];
        final createdBy = groupData['createdBy'] ?? '';

        setState(() {
          _isAdmin = (createdBy == currentUserId);
        });

        if (memberIds.isNotEmpty) {
          final usersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: memberIds)
              .get();

          final members = <Map<String, dynamic>>[];
          for (var doc in usersSnapshot.docs) {
            final userData = doc.data();
            members.add({
              'id': doc.id,
              'username': userData['username'] ?? 'Bilinmeyen Kullanıcı',
              'fullName': userData['fullName'] ?? '',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
              'isAdmin': (doc.id == createdBy),
            });
          }
          setState(() {
            _groupMembers = members;
          });
        }
      }
    } catch (e) {
      print('Grup bilgileri yüklenirken hata: $e');
      _showErrorMessage('Grup bilgileri yüklenirken bir hata oluştu');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      if (widget.chatId.isNotEmpty && currentUserId != null) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({
          'unreadCount.$currentUserId': 0,
        });
      }
    } catch (e) {
      print('Mesajlar okundu olarak işaretlenirken hata: $e');
    }
  }

  //------------------------------------------------------------------------
  // MESAJ GÖNDERME (RESİM VEYA SADECE METİN)
  //------------------------------------------------------------------------
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty && _imageFile == null) return;

    setState(() => _isSending = true);

    try {
      String? imageUrl;
      if (_imageFile != null) {
        final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref =
            FirebaseStorage.instance.ref().child('chat_images').child(fileName);
        await ref.putFile(_imageFile!);
        imageUrl = await ref.getDownloadURL();
      }

      final currentUser = _groupMembers.firstWhere(
        (member) => member['id'] == currentUserId,
        orElse: () => {
          'id': currentUserId,
          'username': 'Bilinmeyen Kullanıcı',
          'profileImageUrl': '',
        },
      );

      await FirebaseFirestore.instance.collection('groupchat').add({
        'chatId': widget.chatId,
        'groupId': widget.groupId,
        'senderId': currentUserId,
        'senderUsername': currentUser['username'],
        'senderProfileImageUrl': currentUser['profileImageUrl'],
        'content': message,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrl': imageUrl,
        'isRead': false,
      });

      final unreadUpdates = <String, dynamic>{};
      for (final member in _groupMembers) {
        final memberId = member['id'] as String?;
        if (memberId != null && memberId != currentUserId) {
          unreadUpdates['unreadCount.$memberId'] = FieldValue.increment(1);
        }
      }

      // Grup belgesi
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'lastMessage': imageUrl != null ? 'Fotoğraf gönderildi' : message,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUserId,
        'lastMessageSenderUsername': currentUser['username'],
        ...unreadUpdates,
      });

      // Chat belgesi
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'lastMessage': imageUrl != null ? 'Fotoğraf gönderildi' : message,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUserId,
        'lastMessageSenderUsername': currentUser['username'],
        ...unreadUpdates,
      });

      _messageController.clear();
      setState(() {
        _imageFile = null;
      });
      _scrollToBottom();
    } catch (e) {
      print('Mesaj gönderilirken hata: $e');
      _showErrorMessage('Mesaj gönderilirken bir hata oluştu');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  //------------------------------------------------------------------------
  // RESİM SEÇME
  //------------------------------------------------------------------------
  Future<void> _pickImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Resim seçilirken hata: $e');
      _showErrorMessage('Resim seçilirken bir hata oluştu');
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resim Kaynağı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  //------------------------------------------------------------------------
  // BOTTOM SHEET: GRUP BİLGİSİ
  //------------------------------------------------------------------------
  void _showGroupInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _buildGroupInfo(),
        ),
      ),
    );
  }

  Widget _buildGroupInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: (widget.groupImageUrl != null &&
                              widget.groupImageUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(widget.groupImageUrl!)
                          : null,
                      child: (widget.groupImageUrl == null ||
                              widget.groupImageUrl!.isEmpty)
                          ? const Icon(Icons.group, size: 50)
                          : null,
                    ),
                    if (_isAdmin)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          child: IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: _showEditGroupDialog,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.groupName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_groupMembers.length} üye',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _showAddMembersDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Üye Ekle'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Grup Üyeleri',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_groupMembers.length} kişi',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),

          /// ÜYE LİSTESİ
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _groupMembers.length,
            itemBuilder: (context, index) {
              final member = _groupMembers[index];
              final isMe = member['id'] == currentUserId;

              return ListTile(
                onTap: () {
                  // Üye profilini aç
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => ProfileScreen(userId: member['id']),
                    ),
                  );
                },
                leading: CircleAvatar(
                  backgroundImage: (member['profileImageUrl'] != null &&
                          member['profileImageUrl'].isNotEmpty)
                      ? CachedNetworkImageProvider(member['profileImageUrl'])
                      : null,
                  child: (member['profileImageUrl'] == null ||
                          member['profileImageUrl'].isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(member['username'])),
                    if (member['isAdmin'])
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    if (isMe)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Sen',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(member['fullName']),
                trailing: _isAdmin && !isMe && !member['isAdmin']
                    ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeGroupMember(member['id']),
                      )
                    : null,
              );
            },
          ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ElevatedButton.icon(
                onPressed: () => _showLeaveGroupDialog(isDelete: true),
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: const Text('Grubu Sil',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          if (!_isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: OutlinedButton.icon(
                onPressed: () => _showLeaveGroupDialog(),
                icon: const Icon(Icons.exit_to_app, color: Colors.red),
                label: const Text(
                  'Gruptan Çık',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddMembersDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _getNonMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                        'Kullanıcılar yüklenirken hata: ${snapshot.error}'),
                  );
                }

                final nonMembers = snapshot.data ?? [];
                if (nonMembers.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child:
                          Text('Gruba ekleyebileceğiniz başka kullanıcı yok'),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.only(bottom: 16),
                      ),
                      Text(
                        'Kullanıcı Ekle',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: nonMembers.length,
                          itemBuilder: (context, index) {
                            final user = nonMembers[index];
                            final userId = user['id'] as String;
                            final username = user['username'] ?? 'Kullanıcı';
                            final fullName = user['fullName'] ?? '';
                            final profileImageUrl =
                                user['profileImageUrl'] ?? '';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: profileImageUrl.isNotEmpty
                                    ? NetworkImage(profileImageUrl)
                                    : null,
                                child: profileImageUrl.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(username),
                              subtitle: Text(fullName),
                              onTap: () async {
                                Navigator.pop(context);
                                await _addMemberToGroup(userId);
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
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getNonMembers() async {
    try {
      final groupMemberIds = <String>{};
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      if (groupDoc.exists) {
        final data = groupDoc.data() as Map<String, dynamic>;
        final memberIds = data['members'] ?? [];
        groupMemberIds.addAll(memberIds.cast<String>());
      }

      final usersSnapshot =
          await FirebaseFirestore.instance.collection('users').get();

      final nonMembers = <Map<String, dynamic>>[];
      for (var doc in usersSnapshot.docs) {
        if (!groupMemberIds.contains(doc.id)) {
          final userData = doc.data();
          nonMembers.add({
            'id': doc.id,
            'username': userData['username'] ?? 'Kullanıcı',
            'fullName': userData['fullName'] ?? '',
            'profileImageUrl': userData['profileImageUrl'] ?? '',
          });
        }
      }
      return nonMembers;
    } catch (e) {
      print('Kullanıcıları yüklerken hata: $e');
      return [];
    }
  }

  Future<void> _removeGroupMember(String memberId) async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'members': FieldValue.arrayRemove([memberId]),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'participants': FieldValue.arrayRemove([memberId]),
      });

      setState(() {
        _groupMembers.removeWhere((m) => m['id'] == memberId);
      });

      CustomSnackBar.show(
        context: context,
        message: 'Üye gruptan çıkarıldı',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Üye çıkarılırken hata: $e');
      _showErrorMessage('Üye çıkarılırken bir hata oluştu');
    }
  }

  void _showLeaveGroupDialog({bool isDelete = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDelete ? 'Grubu Sil' : 'Gruptan Çık'),
        content: Text(
          isDelete
              ? 'Bu grubu silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'
              : 'Bu gruptan çıkmak istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (isDelete) {
                _deleteGroup();
              } else {
                _leaveGroup();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(isDelete ? 'Sil' : 'Çık'),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup() async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'members': FieldValue.arrayRemove([currentUserId]),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'participants': FieldValue.arrayRemove([currentUserId]),
      });

      Navigator.pop(context);
      CustomSnackBar.show(
        context: context,
        message: 'Gruptan çıktınız',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Gruptan çıkılırken hata: $e');
      _showErrorMessage('Gruptan çıkılırken bir hata oluştu');
    }
  }

  Future<void> _deleteGroup() async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .delete();

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .delete();

      final messagesQuery = await FirebaseFirestore.instance
          .collection('groupchat')
          .where('groupId', isEqualTo: widget.groupId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in messagesQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      Navigator.pop(context);
      CustomSnackBar.show(
        context: context,
        message: 'Grup silindi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Grup silinirken hata: $e');
      _showErrorMessage('Grup silinirken bir hata oluştu');
    }
  }

  void _showEditGroupDialog() {
    final nameController = TextEditingController(text: widget.groupName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grubu Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Grup Adı',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndUpdateGroupImage();
              },
              icon: const Icon(Icons.photo),
              label: const Text('Grup Fotoğrafını Değiştir'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateGroupName(nameController.text.trim());
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpdateGroupImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        final imageFile = File(pickedFile.path);
        final fileName =
            'group_${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final ref = FirebaseStorage.instance
            .ref()
            .child('group_images')
            .child(fileName);

        await ref.putFile(imageFile);
        final imageUrl = await ref.getDownloadURL();

        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .update({'imageUrl': imageUrl});

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({'groupImageUrl': imageUrl});

        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'Grup fotoğrafı güncellendi',
            type: SnackBarType.success,
          );
        }
      }
    } catch (e) {
      print('Grup fotoğrafı güncellenirken hata: $e');
      _showErrorMessage('Grup fotoğrafı güncellenirken bir hata oluştu');
    }
  }

  Future<void> _updateGroupName(String newName) async {
    if (newName.isEmpty) {
      _showErrorMessage('Grup adı boş olamaz');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({'name': newName});

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'groupName': newName});

      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Grup adı güncellendi',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      print('Grup adı güncellenirken hata: $e');
      _showErrorMessage('Grup adı güncellenirken bir hata oluştu');
    }
  }

  //------------------------------------------------------------------------
  // EKRAN YAPISI
  //------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: _showGroupInfoBottomSheet,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: (widget.groupImageUrl != null &&
                        widget.groupImageUrl!.isNotEmpty)
                    ? CachedNetworkImageProvider(widget.groupImageUrl!)
                    : null,
                child: (widget.groupImageUrl == null ||
                        widget.groupImageUrl!.isEmpty)
                    ? const Icon(Icons.group, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      '${_groupMembers.length} üye',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showGroupInfoBottomSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // MESAJ LİSTESİ
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groupchat')
                  .where('groupId', isEqualTo: widget.groupId)
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  print('Firestore Sorgu Hatası: ${snapshot.error}');
                  return const Center(
                    child: Text('Mesajlar yüklenirken bir hata oluştu'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Henüz mesaj yok'),
                  );
                }

                final messages = snapshot.data!.docs;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final doc = messages[index];
                    final msgData = doc.data() as Map<String, dynamic>;
                    final messageId = doc.id;

                    final senderId = msgData['senderId'] as String? ?? '';
                    final senderUsername =
                        msgData['senderUsername'] as String? ??
                            'Bilinmeyen Kullanıcı';
                    final senderProfileImageUrl =
                        msgData['senderProfileImageUrl'] as String? ?? '';
                    final timestamp = msgData['timestamp'] as Timestamp?;
                    final content = msgData['content'] as String? ?? '';
                    final imageUrl = msgData['imageUrl'] as String?;
                    final voiceUrl = msgData['voiceUrl'] as String?;
                    final isMine = (senderId == currentUserId);

                    // Tarih ayracı
                    final bool showDate = (index == 0) ||
                        _shouldShowDate(
                          messages[index],
                          index > 0 ? messages[index - 1] : null,
                        );

                    return Column(
                      children: [
                        if (showDate) _buildDateSeparator(timestamp),
                        GestureDetector(
                          onLongPress: () {
                            // Mesaj Sil / Düzenle menüsü
                            showModalBottomSheet(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.delete,
                                          color: Colors.red),
                                      title: const Text('Mesajı Sil'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _deleteMessage(messageId);
                                      },
                                    ),
                                    if (isMine)
                                      ListTile(
                                        leading: const Icon(Icons.edit),
                                        title: const Text('Mesajı Düzenle'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _showEditMessageDialog(
                                              messageId, content);
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisAlignment: isMine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMine) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage:
                                      senderProfileImageUrl.isNotEmpty
                                          ? CachedNetworkImageProvider(
                                              senderProfileImageUrl)
                                          : null,
                                  child: senderProfileImageUrl.isEmpty
                                      ? const Icon(Icons.person, size: 16)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMine)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4, bottom: 2),
                                        child: Text(
                                          senderUsername,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    MessageBubble(
                                      message: content,
                                      isMe: isMine,
                                      time:
                                          timestamp?.toDate() ?? DateTime.now(),
                                      imageUrl: imageUrl,
                                      voiceUrl: voiceUrl,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Eğer resim seçtiyseniz
          if (_imageFile != null)
            Container(
              height: 70,
              width: double.infinity,
              color: Colors.grey[200],
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _imageFile!,
                      height: 60,
                      width: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () {
                      setState(() => _imageFile = null);
                    },
                  ),
                ],
              ),
            ),

          // MESAJ GONDERME ALANI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo),
                            title: const Text('Fotoğraf'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickImage();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.camera_alt),
                            title: const Text('Kamera'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickImage();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // SES KAYIT Butonu
                IconButton(
                  icon: _isRecording
                      ? const Icon(Icons.stop, color: Colors.red)
                      : const Icon(Icons.mic),
                  onPressed: () async {
                    if (!_isRecording) {
                      await _startRecording();
                    } else {
                      final path = await _stopRecording();
                      if (path != null) {
                        await _uploadVoiceAndSend(path);
                      }
                    }
                  },
                ),

                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                  ),
                ),

                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Colors.blue),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TARİH AYIRICI
  Widget _buildDateSeparator(Timestamp? timestamp) {
    if (timestamp == null) return const SizedBox.shrink();
    final date = timestamp.toDate();
    final now = DateTime.now();
    String dateText;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      dateText = 'Bugün';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      dateText = 'Dün';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                dateText,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  /// Hangi tarihteyiz -> Tarih değişti mi kontrol
  bool _shouldShowDate(
      DocumentSnapshot currentDoc, DocumentSnapshot? previousDoc) {
    if (previousDoc == null) return true;
    final currentData = currentDoc.data() as Map<String, dynamic>;
    final previousData = previousDoc.data() as Map<String, dynamic>;
    final currentTimestamp = currentData['timestamp'] as Timestamp?;
    final previousTimestamp = previousData['timestamp'] as Timestamp?;
    if (currentTimestamp == null || previousTimestamp == null) return false;

    final currentDate = currentTimestamp.toDate();
    final previousDate = previousTimestamp.toDate();

    return (currentDate.year != previousDate.year) ||
        (currentDate.month != previousDate.month) ||
        (currentDate.day != previousDate.day);
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      CustomSnackBar.show(
        context: context,
        message: message,
        type: SnackBarType.error,
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Yeni üye ekleme
  Future<void> _addMemberToGroup(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'members': FieldValue.arrayUnion([userId]),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'participants': FieldValue.arrayUnion([userId]),
        'unreadCount.$userId': 0,
      });

      setState(() {
        _groupMembers.add({
          'id': userId,
          'username': 'Yükleniyor...',
          'fullName': '',
          'profileImageUrl': '',
          'isAdmin': false,
        });
      });

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        setState(() {
          final index = _groupMembers.indexWhere((m) => m['id'] == userId);
          if (index != -1) {
            _groupMembers[index] = {
              'id': userId,
              'username': userData?['username'] ?? 'Kullanıcı',
              'fullName': userData?['fullName'] ?? '',
              'profileImageUrl': userData?['profileImageUrl'] ?? '',
              'isAdmin': false,
            };
          }
        });
      }

      CustomSnackBar.show(
        context: context,
        message: 'Kullanıcı gruba eklendi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Üye eklenirken hata: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Üye eklenirken bir hata oluştu: $e',
        type: SnackBarType.error,
      );
    }
  }
}
