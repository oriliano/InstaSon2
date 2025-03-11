import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/bordo_mavi_icon.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<bool> _isUsernameAvailable(String username) async {
    final result = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .where('username', isEqualTo: username)
        .get();

    return result.docs.isEmpty;
  }

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Kullanıcı adının benzersiz olup olmadığını kontrol et
        final usernameQuery = await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .where('username', isEqualTo: _usernameController.text.trim())
            .get();
        
        if (usernameQuery.docs.isNotEmpty) {
          throw Exception('Bu kullanıcı adı zaten kullanılıyor');
        }

        // Firebase Authentication ile kullanıcı oluştur
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // E-posta doğrulama maili gönder
        await userCredential.user!.sendEmailVerification();

        // Firestore'da kullanıcı belgesi oluştur
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(userCredential.user!.uid)
            .set({
              'userId': userCredential.user!.uid,
              'username': _usernameController.text.trim(),
              'fullName': _fullNameController.text.trim(),
              'email': _emailController.text.trim(),
              'bio': '',
              'profileImageUrl': '',
              'followers': [],
              'following': [],
              'createdAt': FieldValue.serverTimestamp(),
            });

        if (!mounted) return;
        
        // E-posta doğrulama ekranına yönlendir
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('E-posta Doğrulama'),
            content: const Text(
              'Hesabınızı doğrulamak için e-posta adresinize gönderilen bağlantıya tıklayın.\n\n'
              'E-posta gelmediyse spam klasörünü kontrol edin.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      } on FirebaseAuthException catch (e) {
        String errorMessage;
        
        switch (e.code) {
          case 'email-already-in-use':
            errorMessage = 'Bu e-posta adresi zaten kullanılıyor';
            break;
          case 'weak-password':
            errorMessage = 'Şifre çok zayıf';
            break;
          case 'invalid-email':
            errorMessage = 'Geçersiz e-posta adresi';
            break;
          default:
            errorMessage = 'Bir hata oluştu: ${e.message}';
        }
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: errorMessage,
          type: SnackBarType.error,
        );
      } catch (e) {
        print('Kayıt olurken hata oluştu: $e');
        
        if (!mounted) return;
        
        CustomSnackBar.show(
          context: context,
          message: 'Kayıt olurken bir hata oluştu: $e',
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
        title: const Text(AppConstants.registerTitle),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  const Center(child: BordoMaviIcon()),
                  const SizedBox(height: 24),

                  // Uygulama adı
                  const Center(
                    child: Text(
                      AppConstants.appName,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Ad Soyad alanı
                  TextFormField(
                    controller: _fullNameController,
                    decoration: AppTheme.inputDecoration(
                      AppConstants.fullNameLabel,
                      hintText: 'Ad Soyad',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppConstants.fullNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Kullanıcı adı alanı
                  TextFormField(
                    controller: _usernameController,
                    decoration: AppTheme.inputDecoration(
                      AppConstants.usernameLabel,
                      hintText: 'kullanici_adi',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppConstants.usernameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // E-posta alanı
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: AppTheme.inputDecoration(
                      AppConstants.emailLabel,
                      hintText: 'ornek@email.com',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppConstants.emailRequired;
                      }
                      if (!value.contains('@')) {
                        return AppConstants.invalidEmail;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Şifre alanı
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: AppConstants.passwordLabel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppConstants.passwordRequired;
                      }
                      if (value.length < 6) {
                        return AppConstants.passwordTooShort;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Kayıt ol butonu
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              AppConstants.registerButton,
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Giriş yap yönlendirmesi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Zaten bir hesabınız var mı?'),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text(AppConstants.loginButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
