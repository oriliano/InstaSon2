import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';
import '../widgets/custom_snackbar.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: _emailController.text.trim(),
        );
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: 'Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.',
          type: SnackBarType.success,
        );
        
        Navigator.pop(context);
      } on FirebaseAuthException catch (e) {
        String errorMessage;
        
        if (e.code == 'user-not-found') {
          errorMessage = 'Bu e-posta adresiyle kayıtlı bir kullanıcı bulunamadı.';
        } else {
          errorMessage = 'Şifre sıfırlama bağlantısı gönderilemedi: ${e.message}';
        }
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: errorMessage,
          type: SnackBarType.error,
        );
      } catch (e) {
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: 'Şifre sıfırlama bağlantısı gönderilemedi: $e',
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Şifremi Unuttum'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Şifrenizi sıfırlamak için e-posta adresinizi girin.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: AppConstants.emailLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppConstants.emailRequired;
                  }
                  
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value)) {
                    return AppConstants.invalidEmail;
                  }
                  
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _resetPassword,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Şifre Sıfırlama Bağlantısı Gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
