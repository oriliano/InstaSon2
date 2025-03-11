import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/bordo_mavi_icon.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isAnonymousLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        print('GİRİŞ BAŞLANIYOR: ${_emailController.text.trim()}');

        final userCredential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // E-posta doğrulama kontrolü
        if (!userCredential.user!.emailVerified) {
          // E-posta doğrulama maili gönder
          await userCredential.user!.sendEmailVerification();

          // Kullanıcıyı çıkış yaptır
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;

          // E-posta doğrulama uyarısı göster
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('E-posta Doğrulama Gerekli'),
              content: const Text(
                'Hesabınızı doğrulamak için e-posta adresinize gönderilen bağlantıya tıklayın.\n\n'
                'E-posta gelmediyse spam klasörünü kontrol edin.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
          return;
        }

        print(
            'Giriş başarılı, kullanıcı ID: ${FirebaseAuth.instance.currentUser?.uid}');

        if (!mounted) return;

        // Başarılı giriş sonrası ana sayfaya yönlendir
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/main', (route) => false);
      } on FirebaseAuthException catch (e) {
        String errorMessage;
        print('Firebase Auth Hatası: ${e.code}');

        switch (e.code) {
          case 'user-not-found':
            errorMessage = AppConstants.userNotFoundError;
            break;
          case 'wrong-password':
            errorMessage = AppConstants.wrongPasswordError;
            break;
          default:
            errorMessage = 'Giriş yapılırken bir hata oluştu: ${e.message}';
        }

        if (!mounted) return;

        CustomSnackBar.show(
          context: context,
          message: errorMessage,
          type: SnackBarType.error,
        );
      } catch (e) {
        print('Beklenmeyen hata: $e');

        if (!mounted) return;

        CustomSnackBar.show(
          context: context,
          message: AppConstants.loginError,
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

  Future<void> _loginAnonymously() async {
    setState(() {
      _isAnonymousLoading = true;
    });

    try {
      print('ANONİM GİRİŞ BAŞLANIYOR');

      await FirebaseAuth.instance.signInAnonymously();

      print(
          'Anonim giriş başarılı, kullanıcı ID: ${FirebaseAuth.instance.currentUser?.uid}');

      if (!mounted) return;

      // Başarılı anonim giriş sonrası ana sayfaya yönlendir
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    } catch (e) {
      print('Anonim giriş hatası: $e');

      if (!mounted) return;

      CustomSnackBar.show(
        context: context,
        message: 'Anonim giriş yapılırken bir hata oluştu',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAnonymousLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      // Basit e-posta doğrulama
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
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Şifremi unuttum
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: const Text(AppConstants.forgotPasswordButton),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Giriş yap butonu
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              AppConstants.loginButton,
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Anonim Giriş butonu

                  // Kayıt ol yönlendirmesi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Hesabınız yok mu?'),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text(AppConstants.createAccountButton),
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
