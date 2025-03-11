import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> startCall(String callerId, String calleeId) async {
    String callId = _firestore.collection('calls').doc().id;

    // Firestore'da yeni bir çağrı başlat
    await _firestore.collection('calls').doc(callId).set({
      'callerId': callerId,
      'calleeId': calleeId,
      'callStatus': 'ringing', // Çalıyor
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Karşı tarafa FCM bildirimi gönder
    await sendCallNotification(calleeId, callId);
  }

  Future<void> sendCallNotification(String calleeId, String callId) async {
    // Firestore'da alıcı kullanıcının token'ını al
    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(calleeId).get();
    String? token = userDoc.get('fcmToken');

    if (token != null) {
      await FirebaseMessaging.instance.sendMessage(
        to: token,
        data: {
          'type': 'incoming_call',
          'callId': callId,
        },
      );
    }
  }
}
