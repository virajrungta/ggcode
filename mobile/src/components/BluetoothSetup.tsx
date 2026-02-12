import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Modal, ActivityIndicator } from 'react-native';
import { Bluetooth, Check, X, Wifi, AlertCircle } from 'lucide-react-native';
import { Theme } from '../theme';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { FadeIn, SlideInDown } from 'react-native-reanimated';

interface BluetoothSetupProps {
  onClose: () => void;
  onConnect: (potName: string) => void;
}

type SetupStatus = 'scanning' | 'found' | 'connecting' | 'success' | 'error';

export default function BluetoothSetup({ onClose, onConnect }: BluetoothSetupProps) {
  const [status, setStatus] = useState<SetupStatus>('scanning');
  const insets = useSafeAreaInsets();
  
  useEffect(() => {
    const scanTimer = setTimeout(() => {
      setStatus('found');
    }, 2500);

    return () => clearTimeout(scanTimer);
  }, []);

  const handleConnect = () => {
    setStatus('connecting');
    setTimeout(() => {
      setStatus('success');
      setTimeout(() => {
        onConnect('SMART POT 01');
      }, 1200);
    }, 1500);
  };

  const getStatusContent = () => {
    switch (status) {
      case 'scanning':
        return {
          icon: <ActivityIndicator size="small" color={Theme.colors.primary} />,
          title: 'SCANNING FOR DEVICES',
          description: 'Ensure your Smart Pot is powered and in range.',
          showButton: false,
        };
      case 'found':
        return {
          icon: <Bluetooth size={24} color={Theme.colors.primary} />,
          title: 'DEVICE LOCATED',
          description: 'Smart Pot GG-X1 is broadcasting.',
          showButton: true,
          buttonText: 'INITIALIZE CONNECTION',
        };
      case 'connecting':
        return {
          icon: <ActivityIndicator size="small" color={Theme.colors.primary} />,
          title: 'ESTABLISHING PROTOCOL',
          description: 'Securing encrypted wireless link...',
          showButton: false,
        };
      case 'success':
        return {
          icon: <Check size={24} color="#00FF00" />,
          title: 'LINK ESTABLISHED',
          description: 'System initialization complete.',
          showButton: false,
        };
      case 'error':
        return {
          icon: <AlertCircle size={24} color={Theme.colors.statusBad} />,
          title: 'PROTOCOL FAILURE',
          description: 'Encryption handshake failed.',
          showButton: true,
          buttonText: 'RETRY PROTOCOL',
        };
    }
  };

  const content = getStatusContent();

  return (
    <Modal transparent animationType="fade">
      <View style={styles.overlay}>
        <TouchableOpacity 
          style={styles.backdrop} 
          activeOpacity={1} 
          onPress={onClose}
        />
        
        <Animated.View 
          entering={SlideInDown.duration(400).springify()} 
          style={[styles.modalContainer, { paddingBottom: insets.bottom + 40 }]}
        >
          {/* Header */}
          <View style={styles.modalHeader}>
            <View style={styles.badgeContainer}>
              <View style={styles.badgeLine} />
              <Text style={styles.badgeText}>HARDWARE</Text>
            </View>
            <TouchableOpacity 
              onPress={onClose}
              style={styles.closeButton}
            >
              <X size={20} color="#fff" />
            </TouchableOpacity>
          </View>

          <View style={styles.content}>
            {/* Status Icon */}
            <View style={[
              styles.iconContainer,
              status === 'success' && { borderColor: '#00FF00' },
              status === 'error' && { borderColor: Theme.colors.statusBad },
            ]}>
              {content.icon}
            </View>

            {/* Status Text */}
            <Text style={styles.title}>{content.title}</Text>
            <Text style={styles.description}>{content.description}</Text>

            {/* Device Info (when found) */}
            {(status === 'found' || status === 'connecting') && (
              <View style={styles.deviceCard}>
                <View style={styles.deviceIcon}>
                  <Wifi size={18} color={Theme.colors.primary} />
                </View>
                <View style={styles.deviceInfo}>
                  <Text style={styles.deviceName}>SMART POT GG-X1</Text>
                  <Text style={styles.deviceId}>BROADCASTING ID: F4:A2:89</Text>
                </View>
                {status === 'connecting' && (
                  <ActivityIndicator size="small" color={Theme.colors.primary} />
                )}
              </View>
            )}

            {/* Action Button */}
            {content.showButton && (
              <TouchableOpacity
                onPress={handleConnect}
                activeOpacity={0.8}
                style={styles.primaryButton}
              >
                <Text style={styles.primaryButtonText}>{content.buttonText}</Text>
              </TouchableOpacity>
            )}
            
            {/* Scanning indicator */}
            {status === 'scanning' && (
              <View style={styles.scanningInfo}>
                <View style={styles.scanningDot} />
                <Text style={styles.scanningText}>RADIO FREQUENCY ACTIVE</Text>
              </View>
            )}
          </View>
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
  },
  modalContainer: {
    backgroundColor: '#050A07',
    borderTopWidth: 1,
    borderColor: '#333',
    padding: 24,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 32,
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  badgeLine: {
    width: 24,
    height: 2,
    backgroundColor: Theme.colors.primary,
  },
  badgeText: {
    color: Theme.colors.primary,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 2,
  },
  closeButton: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#333',
  },
  content: {
    alignItems: 'center',
  },
  iconContainer: {
    width: 80,
    height: 80,
    backgroundColor: '#0F1612',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
    borderWidth: 1,
    borderColor: '#333',
  },
  title: {
    fontSize: 20,
    fontWeight: '800',
    color: '#fff',
    textAlign: 'center',
    marginBottom: 12,
    letterSpacing: 1,
  },
  description: {
    fontSize: 14,
    color: '#888',
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 32,
    paddingHorizontal: 20,
  },
  deviceCard: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '100%',
    padding: 16,
    backgroundColor: '#0F1612',
    borderWidth: 1,
    borderColor: '#222',
    marginBottom: 32,
  },
  deviceIcon: {
    width: 44,
    height: 44,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#333',
  },
  deviceInfo: {
    flex: 1,
    marginLeft: 16,
  },
  deviceName: {
    fontSize: 14,
    fontWeight: '700',
    color: '#fff',
    letterSpacing: 0.5,
  },
  deviceId: {
    fontSize: 11,
    color: '#666',
    marginTop: 2,
    fontWeight: '600',
  },
  primaryButton: {
    width: '100%',
    paddingVertical: 18,
    backgroundColor: Theme.colors.primary,
    alignItems: 'center',
  },
  primaryButtonText: {
    fontSize: 14,
    fontWeight: '800',
    color: '#000',
    letterSpacing: 1.5,
  },
  scanningInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 16,
  },
  scanningDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Theme.colors.primary,
    marginRight: 8,
  },
  scanningText: {
    fontSize: 11,
    fontWeight: '700',
    color: '#666',
    letterSpacing: 1,
  },
});
