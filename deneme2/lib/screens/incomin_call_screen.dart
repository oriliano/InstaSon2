import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IncomingCallScreen extends StatelessWidget {
  final String callId;
  final String calleeId;

  IncomingCallScreen({required this.callId, required this.calleeId});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void acceptCall() async {
    await _firestore.collection('calls').doc(callId).update({
      'callStatus': 'accepted',
    });

    // Arama ekranına yönlendirme yapılabilir
    print("Çağrı kabul edildi!");
  }

  void rejectCall() async {
    await _firestore.collection('calls').doc(callId).update({
      'callStatus': 'rejected',
    });

    // Geri dönüş yapılabilir
    print("Çağrı reddedildi.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gelen Çağrı")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Bir çağrı alıyorsunuz..."),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: acceptCall,
                child: Text("Kabul Et"),
              ),
              SizedBox(width: 20),
              ElevatedButton(
                onPressed: rejectCall,
                child: Text("Reddet"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
