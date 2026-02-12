import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TextInput, TouchableOpacity, Dimensions, KeyboardAvoidingView, Platform, ImageBackground, ActivityIndicator } from 'react-native';
import { Theme } from '../theme';
import Animated, { FadeInDown, FadeInUp } from 'react-native-reanimated';
import { ArrowRight, AlertCircle } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { signIn, signUp, onAuthChanged } from '../firebase';

const { width, height } = Dimensions.get('window');

interface LoginScreenProps {
  navigation: any;
}

export default function LoginScreen({ navigation }: LoginScreenProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [checkingAuth, setCheckingAuth] = useState(true);
  const insets = useSafeAreaInsets();

  // Check if user is already signed in
  useEffect(() => {
    const unsubscribe = onAuthChanged((user) => {
      setCheckingAuth(false);
      if (user) {
        navigation.replace('Main');
      }
    });
    return unsubscribe;
  }, []);

  const handleLogin = async () => {
    if (!email.trim() || !password.trim()) {
      setError('Please enter email and password.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      if (isSignUp) {
        await signUp(email.trim(), password);
      } else {
        await signIn(email.trim(), password);
      }
      navigation.replace('Main');
    } catch (err: any) {
      let message = 'Authentication failed.';
      const code = err?.code;
      
      if (code === 'auth/user-not-found') message = 'No account found with this email.';
      else if (code === 'auth/wrong-password') message = 'Incorrect password.';
      else if (code === 'auth/invalid-email') message = 'Invalid email format.';
      else if (code === 'auth/email-already-in-use') message = 'Email already registered.';
      else if (code === 'auth/weak-password') message = 'Password must be at least 6 characters.';
      else if (code === 'auth/invalid-credential') message = 'Invalid credentials. Check email and password.';
      else if (code === 'auth/too-many-requests') message = 'Too many attempts. Try again later.';
      else message = err?.message || message;

      setError(message);
    } finally {
      setLoading(false);
    }
  };

  if (checkingAuth) {
    return (
      <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator size="large" color={Theme.colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ImageBackground
        source={{ uri: 'https://images.unsplash.com/photo-1518531933037-91b2f5f229cc?q=80&w=2727&auto=format&fit=crop' }}
        style={styles.backgroundImage}
        resizeMode="cover"
      >
        <View style={styles.overlay} />
        
        <KeyboardAvoidingView 
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={[styles.content, { paddingTop: insets.top + 20 }]}
        >
          <Animated.View entering={FadeInUp.duration(1000).delay(200)} style={styles.heroSection}>
            <View style={styles.badgeContainer}>
              <View style={styles.badgeLine} />
              <Text style={styles.badgeText}>AI POWERED</Text>
            </View>
            <Text style={styles.titleMain}>GREEN</Text>
            <Text style={styles.titleSub}>GENIUS</Text>
            <Text style={styles.tagline}>Identify and grow with intelligence.</Text>
          </Animated.View>

          <Animated.View entering={FadeInDown.duration(1000).delay(400)} style={styles.formSection}>
            {/* Error Banner */}
            {error && (
              <View style={styles.errorBanner}>
                <AlertCircle size={16} color="#FF4444" />
                <Text style={styles.errorText}>{error}</Text>
              </View>
            )}

            <View style={styles.inputGroup}>
                <Text style={styles.inputLabel}>EMAIL</Text>
                <TextInput 
                    style={styles.input} 
                    placeholder="viraj@example.com"
                    placeholderTextColor="#666"
                    value={email}
                    onChangeText={(text) => { setEmail(text); setError(null); }}
                    autoCapitalize="none"
                    keyboardType="email-address"
                    editable={!loading}
                />
            </View>

            <View style={styles.inputGroup}>
                <Text style={styles.inputLabel}>PASSWORD</Text>
                <TextInput 
                    style={styles.input} 
                    placeholder="••••••••" 
                    placeholderTextColor="#666"
                    secureTextEntry
                    value={password}
                    onChangeText={(text) => { setPassword(text); setError(null); }}
                    editable={!loading}
                />
            </View>

            <TouchableOpacity 
                activeOpacity={0.8}
                style={[styles.submitButton, loading && styles.submitButtonDisabled]} 
                onPress={handleLogin}
                disabled={loading}
            >
                {loading ? (
                  <ActivityIndicator color="#000" />
                ) : (
                  <>
                    <Text style={styles.submitButtonText}>
                      {isSignUp ? 'CREATE ACCOUNT' : 'ENTER GARDEN'}
                    </Text>
                    <ArrowRight size={24} color="#000" />
                  </>
                )}
            </TouchableOpacity>

            <View style={styles.footer}>
                <Text style={styles.footerText}>
                  {isSignUp ? 'Already have access?' : 'New here?'}
                </Text>
                <TouchableOpacity onPress={() => { setIsSignUp(!isSignUp); setError(null); }}>
                    <Text style={styles.linkText}>
                      {isSignUp ? 'Sign In' : 'Create Access'}
                    </Text>
                </TouchableOpacity>
            </View>
          </Animated.View>
        </KeyboardAvoidingView>
      </ImageBackground>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050A07',
  },
  backgroundImage: {
    flex: 1,
    width: '100%',
  },
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 10, 5, 0.75)',
  },
  content: {
    flex: 1,
    paddingHorizontal: 32,
    justifyContent: 'space-between',
    paddingBottom: 50,
  },
  heroSection: {
    marginTop: 60,
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 12,
  },
  badgeLine: {
    width: 24,
    height: 2,
    backgroundColor: '#D4FF00',
  },
  badgeText: {
    color: '#D4FF00',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 2,
  },
  titleMain: {
    fontSize: 64,
    fontWeight: '800',
    color: '#FFFFFF',
    letterSpacing: -2,
    lineHeight: 60,
    includeFontPadding: false,
  },
  titleSub: {
    fontSize: 64,
    fontWeight: '800',
    color: '#666', 
    letterSpacing: -2,
    lineHeight: 64,
    includeFontPadding: false,
  },
  tagline: {
    fontSize: 18,
    color: '#ccc',
    marginTop: 16,
    maxWidth: '80%',
    lineHeight: 26,
    fontFamily: Platform.OS === 'ios' ? 'Georgia' : 'serif',
    fontStyle: 'italic',
  },
  formSection: {
    marginBottom: 40,
    gap: 32,
  },
  errorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 68, 68, 0.15)',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderColor: 'rgba(255, 68, 68, 0.3)',
    gap: 10,
  },
  errorText: {
    color: '#FF6666',
    fontSize: 13,
    fontWeight: '600',
    flex: 1,
  },
  inputGroup: {
    gap: 12,
  },
  inputLabel: {
    color: '#D4FF00',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
  },
  input: {
    borderBottomWidth: 1,
    borderBottomColor: '#333',
    color: '#fff',
    fontSize: 18,
    paddingVertical: 12,
    fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace',
  },
  submitButton: {
    backgroundColor: '#D4FF00',
    height: 64,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
    marginTop: 16,
  },
  submitButtonDisabled: {
    opacity: 0.7,
    justifyContent: 'center',
  },
  submitButtonText: {
    color: '#000',
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: 1,
  },
  footer: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 24,
  },
  footerText: {
    color: '#666',
  },
  linkText: {
    color: '#fff',
    fontWeight: '600',
    textDecorationLine: 'underline',
  },
});
