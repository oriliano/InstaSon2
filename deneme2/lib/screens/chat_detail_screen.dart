import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'; // Flutter WebRTC paketi

import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';
import 'profile_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String? chatId;
  final String receiverId;
  final String receiverName;
  final String receiverProfileImageUrl;

  const ChatDetailScreen({
    Key? key,
    this.chatId,
    required this.receiverId,
    required this.receiverName,
    required this.receiverProfileImageUrl,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  String? _chatId;
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  File? _selectedImage;
  bool _showAttachmentOptions = false;

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _checkReceiverExists();
    _loadChat();

    if (_chatId != null) {
      _markMessagesAsRead();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  //---------------------------------------------------------------------------//
  //                          MESAJ SİLME VE DÜZENLEME                         //
  //---------------------------------------------------------------------------//

  Future<void> _deleteMessage(
      String messageId, Map<String, dynamic> messageData) async {
    if (_chatId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .delete();

      final lastMessageQuery = await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .where('chatId', isEqualTo: _chatId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (lastMessageQuery.docs.isNotEmpty) {
        final newLastMsgData = lastMessageQuery.docs.first.data();
        await FirebaseFirestore.instance
            .collection(AppConstants.chatsCollection)
            .doc(_chatId)
            .update({
          'lastMessage': (newLastMsgData['imageUrl'] != null)
              ? (newLastMsgData['content']?.toString()?.isNotEmpty == true
                  ? '${newLastMsgData['content']} 📷'
                  : '📷 Fotoğraf')
              : newLastMsgData['content'] ?? '',
          'lastMessageTime': newLastMsgData['timestamp'],
          'lastMessageSenderId': newLastMsgData['senderId'],
        });
      } else {
        await FirebaseFirestore.instance
            .collection(AppConstants.chatsCollection)
            .doc(_chatId)
            .update({
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSenderId': '',
        });
      }

      CustomSnackBar.show(
        context: context,
        message: 'Mesaj silindi',
        type: SnackBarType.success,
      );
    } catch (e) {
      print('Mesaj silinirken hata: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Mesaj silinirken hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<void> _editMessage(String messageId, String newContent) async {
    if (_chatId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
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
        message: 'Mesaj düzenlenirken hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  void _showEditDialog(String messageId, String currentContent) {
    final TextEditingController editCtrl =
        TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı Düzenle'),
        content: TextField(
          controller: editCtrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = editCtrl.text.trim();
              if (newText.isNotEmpty) {
                Navigator.pop(context);
                await _editMessage(messageId, newText);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(String messageId, Map<String, dynamic> msgData) {
    final isCurrentUser = (msgData['senderId'] == currentUserId);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Mesajı Sil'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(messageId, msgData);
              },
            ),
            if (isCurrentUser)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Mesajı Düzenle'),
                onTap: () {
                  Navigator.pop(ctx);
                  final content = msgData['content'] ?? '';
                  _showEditDialog(messageId, content);
                },
              ),
          ],
        ),
      ),
    );
  }

  //---------------------------------------------------------------------------//
  //               FLUTTER_WEBRTC TEMELLİ GÖRÜNTÜLÜ ARA ENTEGRASYONU         //
  //---------------------------------------------------------------------------//

  // Video arama ekranına geçiş yapan fonksiyon.
  void _startVideoCall() {
    if (_chatId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallScreen(roomId: _chatId!, isCaller: true),
      ),
    );
  }

  //---------------------------------------------------------------------------//
  //                          KONTROL / CHAT OLUŞTURMA                         //
  //---------------------------------------------------------------------------//

  Future<void> _checkReceiverExists() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(widget.receiverId)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;
        Navigator.pop(context);
        CustomSnackBar.show(
          context: context,
          message: 'Bu kullanıcı artık mevcut değil',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      print('Kullanıcı var mı kontrolü hata: $e');
    }
  }

  Future<void> _loadChat() async {
    if (currentUserId == null) return;
    setState(() => _isLoadingMessages = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(widget.receiverId)
          .get();
      if (!userDoc.exists) {
        if (!mounted) return;
        Navigator.pop(context);
        CustomSnackBar.show(
          context: context,
          message: 'Bu kullanıcı artık mevcut değil',
          type: SnackBarType.error,
        );
        return;
      }

      if (_chatId == null) {
        final query = await FirebaseFirestore.instance
            .collection(AppConstants.chatsCollection)
            .where('participants', arrayContains: currentUserId)
            .get();

        for (var doc in query.docs) {
          final participants = List<String>.from(doc['participants']);
          if (participants.contains(widget.receiverId)) {
            _chatId = doc.id;
            break;
          }
        }

        if (_chatId == null) {
          final newChatRef = FirebaseFirestore.instance
              .collection(AppConstants.chatsCollection)
              .doc();

          await newChatRef.set({
            'chatId': newChatRef.id,
            'participants': [currentUserId, widget.receiverId],
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessage': '',
            'lastMessageSenderId': '',
            'unreadCount': {
              currentUserId!: 0,
              widget.receiverId: 0,
            },
          });
          _chatId = newChatRef.id;
        }
      }
    } catch (e) {
      print('Sohbet yüklenirken hata: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Sohbet yüklenirken hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMessages = false);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (_chatId == null || currentUserId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.chatsCollection)
          .doc(_chatId)
          .update({'unreadCount.$currentUserId': 0});

      final unreadMsgs = await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .where('chatId', isEqualTo: _chatId)
          .where('senderId', isNotEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadMsgs.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      print('Mesajları okundu işaretlerken hata: $e');
    }
  }

  //---------------------------------------------------------------------------//
  //                                MESAJ GÖNDERME                              //
  //---------------------------------------------------------------------------//

  Future<void> _sendMessage({String? imageUrl}) async {
    if (_chatId == null || currentUserId == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;

    setState(() => _isSendingMessage = true);

    try {
      final messageId = const Uuid().v4();
      await FirebaseFirestore.instance
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .set({
        'messageId': messageId,
        'chatId': _chatId,
        'senderId': currentUserId,
        'content': text,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'imageUrl': imageUrl,
      });

      final chatRef = FirebaseFirestore.instance
          .collection(AppConstants.chatsCollection)
          .doc(_chatId);

      final chatDoc = await chatRef.get();
      if (chatDoc.exists) {
        final data = chatDoc.data() as Map<String, dynamic>;
        final unread = data['unreadCount'] as Map<String, dynamic>? ?? {};
        final receiverUnread = (unread[widget.receiverId] as int?) ?? 0;

        await chatRef.update({
          'lastMessage': (imageUrl != null)
              ? (text.isNotEmpty ? '$text 📷' : '📷 Fotoğraf')
              : text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSenderId': currentUserId,
          'unreadCount.${widget.receiverId}': receiverUnread + 1,
        });
      }

      _messageController.clear();

      Future.delayed(Duration.zero, () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      print('Mesaj gönderme hata: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Mesaj gönderilirken hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isSendingMessage = false);
      _showAttachmentOptions = false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile =
          await ImagePicker().pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _showAttachmentOptions = false;
        });
        await _uploadImageAndSend();
      }
    } catch (e) {
      print('Fotoğraf seçme hata: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Fotoğraf seçilirken hata oluştu',
        type: SnackBarType.error,
      );
    }
  }

  Future<void> _uploadImageAndSend() async {
    if (_selectedImage == null || _chatId == null || currentUserId == null)
      return;
    setState(() => _isSendingMessage = true);

    try {
      final fileName =
          '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref =
          FirebaseStorage.instance.ref().child('chat_images').child(fileName);

      final uploadTask = ref.putFile(_selectedImage!);
      final snapshot = await uploadTask.whenComplete(() {});
      final imageUrl = await snapshot.ref.getDownloadURL();

      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      print('Fotoğraf yükleme hata: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Fotoğraf yüklenirken hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      setState(() {
        _isSendingMessage = false;
        _selectedImage = null;
      });
    }
  }

  //---------------------------------------------------------------------------//
  //                                WIDGETS                                   //
  //---------------------------------------------------------------------------//

  Widget _buildMessageItem(Map<String, dynamic> message, String messageId) {
    final isCurrentUser = (message['senderId'] == currentUserId);
    final timestamp = message['timestamp'] as Timestamp?;
    final time = (timestamp != null)
        ? DateFormat('HH:mm').format(timestamp.toDate())
        : '';

    final hasImage = (message['imageUrl'] != null &&
        message['imageUrl'].toString().isNotEmpty);

    return GestureDetector(
      onLongPress: () {
        _showMessageOptions(messageId, message);
      },
      child: Align(
        alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: 8,
            left: isCurrentUser ? 50 : 8,
            right: isCurrentUser ? 8 : 50,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrentUser
                ? const Color(0xFFE1F5FE)
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(backgroundColor: Colors.black),
                          backgroundColor: Colors.black,
                          body: Center(
                            child: InteractiveViewer(
                              child: Image.network(
                                message['imageUrl'],
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          message['imageUrl'],
                          width: 200,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return SizedBox(
                              width: 200,
                              height: 150,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (ctx, e, stack) => Container(
                            width: 200,
                            height: 150,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(Icons.error),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              if (message['content'] != null &&
                  message['content'].toString().isNotEmpty)
                Text(
                  message['content'],
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  if (isCurrentUser)
                    Icon(
                      (message['isRead'] == true) ? Icons.done_all : Icons.done,
                      size: 14,
                      color: (message['isRead'] == true)
                          ? Colors.blue
                          : Colors.grey[600],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingMessages) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(userId: widget.receiverId),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: (widget.receiverProfileImageUrl.isNotEmpty)
                    ? CachedNetworkImageProvider(widget.receiverProfileImageUrl)
                    : null,
                child: widget.receiverProfileImageUrl.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(widget.receiverName),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Sohbet detayları
            },
          ),
          // Video arama butonu: Firebase sinyalizasyonu üzerinden flutter_webrtc ile VideoCallScreen'e yönlendirir.
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: _startVideoCall,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: (_chatId == null)
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection(AppConstants.messagesCollection)
                        .where('chatId', isEqualTo: _chatId)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (ctx, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Bir hata oluştu: ${snapshot.error}'),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.chat_bubble_outline,
                                  size: 80, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Henüz mesaj yok',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'İlk mesajı göndererek sohbete başlayın',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      _markMessagesAsRead();

                      final msgs = snapshot.data!.docs;
                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: msgs.length,
                        itemBuilder: (ctx, i) {
                          final doc = msgs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final messageId = doc.id;
                          return _buildMessageItem(data, messageId);
                        },
                      );
                    },
                  ),
          ),
          if (_showAttachmentOptions)
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _showAttachmentOptions = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: () {
                    setState(() {
                      _showAttachmentOptions = !_showAttachmentOptions;
                    });
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  icon: _isSendingMessage
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Color(0xFF800000)),
                  onPressed: _isSendingMessage ? null : () => _sendMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//---------------------------------------------------------------------------//
//                    FLUTTER_WEBRTC VIDEO ARA EKRANI (Firebase ile)          //
//---------------------------------------------------------------------------//

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final bool isCaller; // true: çağrıyı başlatan, false: çağrıyı alan (incoming)
  const VideoCallScreen(
      {Key? key, required this.roomId, required this.isCaller})
      : super(key: key);

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DocumentReference _callDoc;

  @override
  void initState() {
    super.initState();
    _callDoc = _firestore.collection('calls').doc(widget.roomId);
    _initializeRenderers();
    _openUserMedia().then((_) async {
      await _createPeerConnection();
      if (widget.isCaller) {
        _createOffer();
      } else {
        _listenForOffer();
      }
    });
    _listenForRemoteCandidates();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _openUserMedia() async {
    final mediaConstraints = {
      'audio': true,
      'video': {'facingMode': 'user'},
    };
    try {
      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      setState(() {
        _localRenderer.srcObject = _localStream;
      });
    } catch (e) {
      print('User media error: $e');
    }
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    try {
      _peerConnection = await createPeerConnection(configuration);
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onIceCandidate = (candidate) {
        if (candidate != null) {
          // Caller ICE adayları Firestore'a yazsın; callee adayları ise farklı alt koleksiyonda olsun.
          String candidateCollection =
              widget.isCaller ? 'callerCandidates' : 'calleeCandidates';
          _callDoc.collection(candidateCollection).add(candidate.toMap());
          print(
              '${widget.isCaller ? "Caller" : "Callee"} ICE Candidate: ${candidate.candidate}');
        }
      };

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
        }
      };
    } catch (e) {
      print('PeerConnection error: $e');
    }
  }

  // Caller tarafı: offer oluşturup yazma
  Future<void> _createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _callDoc.set({'offer': offer.toMap(), 'callStatus': 'ringing'},
        SetOptions(merge: true));
    print('Caller created offer: ${offer.sdp}');
    _listenForAnswer();
  }

  // Caller tarafı: answer dinleme
  void _listenForAnswer() {
    _callDoc.snapshots().listen((doc) async {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null && data['answer'] != null) {
        final answerData = data['answer'] as Map<String, dynamic>;
        RTCSessionDescription answer =
            RTCSessionDescription(answerData['sdp'], answerData['type']);
        await _peerConnection?.setRemoteDescription(answer);
        print('Caller received answer: ${answer.sdp}');
      }
    });
  }

  // Callee tarafı: offer dinleme ve cevap oluşturma
  void _listenForOffer() {
    _callDoc.snapshots().listen((doc) async {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null && data['offer'] != null) {
        final offerData = data['offer'] as Map<String, dynamic>;
        RTCSessionDescription offer =
            RTCSessionDescription(offerData['sdp'], offerData['type']);
        await _peerConnection?.setRemoteDescription(offer);
        print('Callee received offer: ${offer.sdp}');
        _createAnswer();
      }
    });
  }

  Future<void> _createAnswer() async {
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await _callDoc.set({'answer': answer.toMap()}, SetOptions(merge: true));
    print('Callee created answer: ${answer.sdp}');
  }

  // Her iki taraf için: remote ICE adaylarını dinleme
  void _listenForRemoteCandidates() {
    // Diğer tarafın adaylarını dinlemek için; caller dinlerse calleeCandidates, callee dinlerse callerCandidates
    String remoteCandidateCollection =
        widget.isCaller ? 'calleeCandidates' : 'callerCandidates';
    _callDoc
        .collection(remoteCandidateCollection)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        var data = change.doc.data();
        if (data != null) {
          RTCIceCandidate candidate = RTCIceCandidate(
              data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
          _peerConnection?.addCandidate(candidate);
          print('Added remote candidate: ${candidate.candidate}');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Arama'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: RTCVideoView(_remoteRenderer)),
          Positioned(
            right: 20,
            top: 20,
            width: 120,
            height: 160,
            child: RTCVideoView(_localRenderer, mirror: true),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: ElevatedButton(
              onPressed: () async {
                // Çağrıyı sonlandırmak için Firestore dokümanını temizleyip çıkın
                await _callDoc.delete();
                Navigator.pop(context);
              },
              child: const Text('Aramayı Sonlandır'),
            ),
          ),
        ],
      ),
    );
  }
}
