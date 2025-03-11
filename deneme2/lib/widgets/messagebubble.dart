import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'voice_message_player.dart'; // VoiceMessagePlayer dosyasını ekleyin

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final DateTime time;
  final String? imageUrl;
  final String? voiceUrl;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.time,
    this.imageUrl,
    this.voiceUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 60 : 8,
          right: isMe ? 8 : 60,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[50] : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty) _buildImage(),
        if (voiceUrl != null && voiceUrl!.isNotEmpty)
          VoiceMessagePlayer(voiceUrl: voiceUrl!, isMe: isMe),
        if (message.isNotEmpty) _buildTextMessage(),
        _buildTimeStamp(),
      ],
    );
  }

  Widget _buildImage() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        placeholder: (context, url) => SizedBox(
          height: 150,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isMe ? Colors.blue : Colors.grey,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => const SizedBox(
          height: 150,
          child: Center(
            child: Icon(Icons.error, color: Colors.red),
          ),
        ),
        fit: BoxFit.cover,
        width: double.infinity,
      ),
    );
  }

  Widget _buildTextMessage() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.blue[800] : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTimeStamp() {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4, left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            DateFormat('HH:mm').format(time),
            style: TextStyle(
              fontSize: 10,
              color: isMe ? Colors.blue[800] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
