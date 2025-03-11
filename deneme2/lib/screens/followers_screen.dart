import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instason/widgets/custom_snackbar.dart';
import '../utils/constants.dart';
import 'profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowersScreen extends StatefulWidget {
  final String userId;

  const FollowersScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  List<String> _followerIds = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _followers = [];

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
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
      final List<dynamic> followerIds = userData['followers'] ?? [];

      final List<Map<String, dynamic>> validFollowers = [];

      for (var followerId in followerIds) {
        try {
          final followerDoc = await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(followerId)
              .get();

          // Belge varsa ekle
          if (followerDoc.exists) {
            final followerData = followerDoc.data() as Map<String, dynamic>;
            validFollowers.add({
              'id': followerId,
              ...followerData,
            });
          }
        } catch (e) {
          print('Takipçi yüklenirken hata: $e');
          continue;
        }
      }

      setState(() {
        _followers = validFollowers;
      });
    } catch (e) {
      print('Takipçiler yüklenirken hata oluştu: $e');
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: 'Takipçiler yüklenirken bir hata oluştu',
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
        title: const Text('Takipçiler'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _followers.isEmpty
              ? const Center(
                  child: Text('Henüz takipçi yok'),
                )
              : ListView.builder(
                  itemCount: _followers.length,
                  itemBuilder: (context, index) {
                    final followerData = _followers[index];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            followerData['profileImageUrl'] != null &&
                                    followerData['profileImageUrl'].isNotEmpty
                                ? CachedNetworkImageProvider(
                                    followerData['profileImageUrl'])
                                : null,
                        child: followerData['profileImageUrl'] == null ||
                                followerData['profileImageUrl'].isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        followerData['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        followerData['fullName'] ?? '',
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProfileScreen(userId: followerData['id']),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
