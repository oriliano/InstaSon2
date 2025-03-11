import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import '../utils/constants.dart';
import 'profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowingScreen extends StatefulWidget {
  final String userId;

  const FollowingScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  // Başlangıçta veri yüklenmediği için false
  bool _isLoading = false;
  List<Map<String, dynamic>> _following = [];

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(widget.userId)
          .get();

      if (!userDoc.exists) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final List<dynamic> followingIds = userData['following'] ?? [];

      final List<Map<String, dynamic>> validFollowing = [];

      for (var followingId in followingIds) {
        try {
          final followingDoc = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(followingId)
              .get();

          if (followingDoc.exists) {
            final followingData = followingDoc.data() as Map<String, dynamic>;

            // Eğer email kontrolü istemiyorsanız, aşağıdaki satırı kaldırın
            // if (followingData.containsKey('email') &&
            //     (followingData['email'] as String).isNotEmpty) {

            validFollowing.add({
              'id': followingId,
              ...followingData,
            });

            // }
          }
        } catch (e) {
          print('Takip edilen yüklenirken hata: $e');
          continue;
        }
      }
      setState(() {
        _following = validFollowing;
      });
    } catch (e) {
      print('Takip edilenler yüklenirken hata oluştu: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Takip edilenler yüklenirken bir hata oluştu',
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
        title: const Text('Takip Edilenler'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _following.isEmpty
              ? const Center(child: Text('Henüz takip edilen yok'))
              : ListView.builder(
                  itemCount: _following.length,
                  itemBuilder: (context, index) {
                    final followingData = _following[index];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            followingData['profileImageUrl'] != null &&
                                    followingData['profileImageUrl'].isNotEmpty
                                ? CachedNetworkImageProvider(
                                    followingData['profileImageUrl'])
                                : null,
                        child: followingData['profileImageUrl'] == null ||
                                followingData['profileImageUrl'].isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        followingData['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(followingData['fullName'] ?? ''),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProfileScreen(userId: followingData['id']),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
