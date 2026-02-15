import React from 'react';
import { StyleSheet, View, Platform, ViewStyle } from 'react-native';
import { BlurView } from 'expo-blur';
import { Theme } from '../../theme';

interface GlassCardProps {
  children: React.ReactNode;
  style?: ViewStyle;
  intensity?: number;
  tint?: 'light' | 'dark' | 'default' | 'systemThinMaterial' | 'systemMaterial' | 'systemThickMaterial';
  variant?: 'subtle' | 'prominent';
}

export function GlassCard({ 
  children, 
  style, 
  intensity = 20, 
  tint = 'light',
  variant = 'subtle'
}: GlassCardProps) {
  const containerStyle = [
    styles.container,
    variant === 'prominent' && styles.prominent,
    style
  ];

  if (Platform.OS === 'android') {
    // Android has improved blur support but sometimes needs a solid fallback
    // For now we try to use the blur, but add a slightly more opaque background
    return (
      <View style={[containerStyle, styles.androidFallback]}>
        {children}
      </View>
    );
  }

  return (
    <BlurView intensity={intensity} tint={tint} style={containerStyle}>
      <View style={styles.borderOverlay} pointerEvents="none" />
      {children}
    </BlurView>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: Theme.radius.xl,
    overflow: 'hidden',
    position: 'relative',
    backgroundColor: 'rgba(255, 255, 255, 0.65)',
  },
  prominent: {
    backgroundColor: 'rgba(255, 255, 255, 0.85)',
    ...Platform.select({
      web: { boxShadow: '0px 4px 12px rgba(0, 0, 0, 0.1)' },
      default: {
        shadowColor: "#000",
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.1,
        shadowRadius: 12,
      },
    }) as any,
  },
  androidFallback: {
    backgroundColor: '#FFFFFF',
    elevation: 2,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.05)',
  },
  borderOverlay: {
    ...StyleSheet.absoluteFillObject,
    borderRadius: Theme.radius.xl,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.5)',
  },
});
