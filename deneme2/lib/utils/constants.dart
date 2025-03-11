class AppConstants {
  // Uygulama adı
  static const String appName = 'InstaSon';
  
  // Ekran başlıkları
  static const String loginTitle = 'Giriş Yap';
  static const String registerTitle = 'Kayıt Ol';
  
  // Firebase koleksiyon isimleri
  static const String usersCollection = 'users';
  static const String postsCollection = 'posts';
  static const String commentsCollection = 'comments';
  static const String storiesCollection = 'stories';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String notificationsCollection = 'notifications';
  static const String likesCollection = 'likes';
  static const String followersCollection = 'followers';
  static const String followingCollection = 'following';
  
  // Hata mesajları
  static const String loginError = 'Giriş yapılırken bir hata oluştu';
  static const String registerError = 'Kayıt olurken bir hata oluştu';
  static const String userNotFoundError = 'Bu e-posta adresi ile kayıtlı kullanıcı bulunamadı';
  static const String wrongPasswordError = 'Yanlış şifre girdiniz';
  static const String weakPasswordError = 'Şifre çok zayıf';
  static const String emailInUseError = 'Bu e-posta adresi zaten kullanılıyor';
  static const String networkError = 'İnternet bağlantınızı kontrol edin';
  
  // Başarı mesajları
  static const String loginSuccess = 'Başarıyla giriş yapıldı';
  static const String registerSuccess = 'Başarıyla kayıt olundu';
  static const String postSuccess = 'Gönderi başarıyla paylaşıldı';
  static const String storySuccess = 'Hikaye başarıyla paylaşıldı';
  
  // Buton metinleri
  static const String loginButton = 'Giriş Yap';
  static const String registerButton = 'Kayıt Ol';
  static const String forgotPasswordButton = 'Şifremi Unuttum';
  static const String createAccountButton = 'Hesap Oluştur';
  static const String logoutButton = 'Çıkış Yap';
  static const String saveButton = 'Kaydet';
  static const String cancelButton = 'İptal';
  static const String shareButton = 'Paylaş';
  static const String followButton = 'Takip Et';
  static const String unfollowButton = 'Takibi Bırak';
  static const String editProfileButton = 'Profili Düzenle';
  
  // Form etiketleri
  static const String emailLabel = 'E-posta';
  static const String passwordLabel = 'Şifre';
  static const String usernameLabel = 'Kullanıcı Adı';
  static const String fullNameLabel = 'Ad Soyad';
  static const String bioLabel = 'Biyografi';
  static const String searchLabel = 'Ara';
  static const String commentLabel = 'Yorum yap...';
  static const String messageLabel = 'Mesaj yaz...';
  
  // Doğrulama mesajları
  static const String emailRequired = 'E-posta adresi gerekli';
  static const String passwordRequired = 'Şifre gerekli';
  static const String usernameRequired = 'Kullanıcı adı gerekli';
  static const String fullNameRequired = 'Ad soyad gerekli';
  static const String invalidEmail = 'Geçerli bir e-posta adresi girin';
  static const String passwordTooShort = 'Şifre en az 6 karakter olmalı';
  
  // Diğer metinler
  static const String noPostsYet = 'Henüz gönderi yok';
  static const String noStoriesYet = 'Henüz hikaye yok';
  static const String noCommentsYet = 'Henüz yorum yok';
  static const String noNotificationsYet = 'Henüz bildirim yok';
  static const String noMessagesYet = 'Henüz mesaj yok';
  static const String noUsersFound = 'Kullanıcı bulunamadı';
} 