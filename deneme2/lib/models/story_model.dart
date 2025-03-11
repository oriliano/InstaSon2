import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  final String storyId;
  final String userId;
  final String username;
  final String userProfileImageUrl;
  final String mediaUrl;
  final bool isVideo;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy;

  StoryModel({
    required this.storyId,
    required this.userId,
    required this.username,
    required this.userProfileImageUrl,
    required this.mediaUrl,
    required this.isVideo,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'storyId': storyId,
      'userId': userId,
      'username': username,
      'userProfileImageUrl': userProfileImageUrl,
      'mediaUrl': mediaUrl,
      'isVideo': isVideo,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'viewedBy': viewedBy,
    };
  }

  factory StoryModel.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    
    return StoryModel(
      storyId: snapshot.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? '',
      userProfileImageUrl: data['userProfileImageUrl'] ?? '',
      mediaUrl: data['mediaUrl'] ?? '',
      isVideo: data['isVideo'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      viewedBy: List<String>.from(data['viewedBy'] ?? []),
    );
  }

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      storyId: json['storyId'] ?? '',
      userId: json['userId'] ?? '',
      username: json['username'] ?? '',
      userProfileImageUrl: json['userProfileImageUrl'] ?? '',
      mediaUrl: json['mediaUrl'] ?? '',
      isVideo: json['isVideo'] ?? false,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      expiresAt: (json['expiresAt'] as Timestamp).toDate(),
      viewedBy: List<String>.from(json['viewedBy'] ?? []),
    );
  }
} 