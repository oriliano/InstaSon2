import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:instason/widgets/bordo_mavi_icon.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'utils/theme.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase'i özel yapılandırma ile başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Web platformunda Firebase Auth için özel yapılandırma
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  // Firebase Auth için dil kodunu Türkçe olarak ayarla
  FirebaseAuth.instance.setLanguageCode("tr");
  
  // Debug modunda emülatör kullanımı için koşullu kod
  // Bu kısmı sadece geliştirme aşamasında kullanın
  // assert(() {
  //   try {
  //     FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
  //     print('Firebase Auth emülatörü başarıyla ayarlandı');
  //   } catch (e) {
  //     print('Firebase Auth emülatörü ayarlanamadı: $e');
  //   }
  //   return true;
  // }());
  
  // Türkçe zaman çevirileri
  timeago.setLocaleMessages('tr', timeago.TrMessages());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstaSON',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        primaryColor: const Color(0xFF800000), // Bordo
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF800000), // Bordo
          secondary: const Color(0xFF0000CD), // Mavi
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF800000), // Bordo
          foregroundColor: Colors.white,
          elevation: 1,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Color(0xFF800000), // Bordo
          unselectedItemColor: Colors.grey,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF800000), // Bordo
            foregroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF800000), // Bordo
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF800000), // Bordo
            side: const BorderSide(color: Color(0xFF800000)), // Bordo
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            print('Auth durumu değişti: ${snapshot.data?.uid}');
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              print('Firebase bağlantısı bekleniyor...');
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasData && snapshot.data != null) {
              print('Kullanıcı giriş yapmış (${snapshot.data?.uid}), MainScreen\'e yönlendiriliyor');
              return const MainScreen();
            }

            print('Kullanıcı giriş yapmamış, LoginScreen\'e yönlendiriliyor');
            return const LoginScreen();
          },
        ),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/main': (context) => const MainScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkUserAndNavigate();
  }

  Future<void> _checkUserAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null && currentUser.emailVerified) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BordoMaviIcon(),
            SizedBox(height: 24),
            Text(
              'InstaSon',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
