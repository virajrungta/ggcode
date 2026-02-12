import React, { useState, useRef } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator } from 'react-native';
import { CameraView as ExpoCameraView, useCameraPermissions } from 'expo-camera';
import { X, Camera, Aperture } from 'lucide-react-native';
import { Theme } from '../theme';
import { SafeAreaView } from 'react-native-safe-area-context';

interface CameraViewProps {
  onCapture: (base64: string) => void;
  onClose: () => void;
}

export default function CameraView({ onCapture, onClose }: CameraViewProps) {
  const [permission, requestPermission] = useCameraPermissions();
  const cameraRef = useRef<any>(null);
  const [isCapturing, setIsCapturing] = useState(false);

  if (!permission) {
    return <View style={styles.container} />;
  }

  if (!permission.granted) {
    return (
      <View style={styles.container}>
        <SafeAreaView style={styles.permissionContainer}>
          <TouchableOpacity 
            style={styles.closeButtonAbsolute} 
            onPress={onClose}
            hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
          >
            <X size={24} color={Theme.colors.textInverse} />
          </TouchableOpacity>
          
          <View style={styles.permissionContent}>
            <View style={styles.permissionIcon}>
              <Camera size={32} color={Theme.colors.textInverse} />
            </View>
            <Text style={styles.permissionTitle}>Camera Access Required</Text>
            <Text style={styles.permissionText}>
              To identify your plants, we need access to your camera. Your photos are processed securely.
            </Text>
            <TouchableOpacity 
              style={styles.permissionButton} 
              onPress={requestPermission}
              activeOpacity={0.8}
            >
              <Text style={styles.permissionButtonText}>Allow Camera Access</Text>
            </TouchableOpacity>
          </View>
        </SafeAreaView>
      </View>
    );
  }

  const takePicture = async () => {
    if (cameraRef.current && !isCapturing) {
      setIsCapturing(true);
      try {
        const photo = await cameraRef.current.takePictureAsync({
          base64: true,
          quality: 0.7,
        });
        if (photo.base64) {
          onCapture(photo.base64);
        }
      } catch (error) {
        console.error("Error taking picture:", error);
      } finally {
        setIsCapturing(false);
      }
    }
  };

  return (
    <View style={styles.container}>
      <ExpoCameraView 
        style={styles.camera} 
        ref={cameraRef}
      />
      
      {/* Overlay UI - Positioned Absolutely over the Camera */}
      <SafeAreaView style={styles.overlay} pointerEvents="box-none">
          {/* Top Bar */}
          <View style={styles.topBar}>
            <TouchableOpacity 
              style={styles.closeButton} 
              onPress={onClose}
              hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
            >
              <X size={24} color={Theme.colors.textInverse} />
            </TouchableOpacity>
          </View>

          {/* Instructions */}
          <View style={styles.instructionsContainer}>
            <View style={styles.instructionsBadge}>
              <Aperture size={14} color={Theme.colors.textInverse} />
              <Text style={styles.instructionsText}>Center your plant in the frame</Text>
            </View>
          </View>

          {/* Viewfinder Frame */}
          <View style={styles.viewfinderContainer} pointerEvents="none">
            <View style={styles.viewfinder}>
              <View style={[styles.corner, styles.cornerTopLeft]} />
              <View style={[styles.corner, styles.cornerTopRight]} />
              <View style={[styles.corner, styles.cornerBottomLeft]} />
              <View style={[styles.corner, styles.cornerBottomRight]} />
            </View>
          </View>

          {/* Bottom Controls */}
          <View style={styles.bottomBar}>
            <View style={styles.captureContainer}>
              <TouchableOpacity 
                style={[styles.captureButton, isCapturing && styles.captureButtonDisabled]} 
                onPress={takePicture}
                disabled={isCapturing}
                activeOpacity={0.8}
              >
                {isCapturing ? (
                  <ActivityIndicator color={Theme.colors.textPrimary} size="small" />
                ) : (
                  <View style={styles.captureInner} />
                )}
              </TouchableOpacity>
            </View>
            <Text style={styles.captureHint}>Tap to capture</Text>
          </View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#000',
    zIndex: 1000,
  },
  camera: {
    ...StyleSheet.absoluteFillObject,
  },
  overlay: {
    flex: 1,
    justifyContent: 'space-between',
  },
  
  // Top Bar
  topBar: {
    flexDirection: 'row',
    justifyContent: 'flex-start',
    padding: Theme.spacing.l,
    paddingTop: Theme.spacing.m,
  },
  closeButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeButtonAbsolute: {
    position: 'absolute',
    top: 60,
    left: Theme.spacing.l,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Instructions
  instructionsContainer: {
    alignItems: 'center',
    marginTop: Theme.spacing.m,
    position: 'absolute',
    top: 100,
    left: 0,
    right: 0,
  },
  instructionsBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    gap: 6,
  },
  instructionsText: {
    color: Theme.colors.textInverse,
    fontSize: 13,
    fontWeight: '500',
  },

  // Viewfinder
  viewfinderContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewfinder: {
    width: '100%',
    aspectRatio: 1,
    maxWidth: 300,
    maxHeight: 300,
    position: 'relative',
  },
  corner: {
    position: 'absolute',
    width: 32,
    height: 32,
    borderColor: Theme.colors.textInverse,
  },
  cornerTopLeft: {
    top: 0,
    left: 0,
    borderTopWidth: 3,
    borderLeftWidth: 3,
    borderTopLeftRadius: 12,
  },
  cornerTopRight: {
    top: 0,
    right: 0,
    borderTopWidth: 3,
    borderRightWidth: 3,
    borderTopRightRadius: 12,
  },
  cornerBottomLeft: {
    bottom: 0,
    left: 0,
    borderBottomWidth: 3,
    borderLeftWidth: 3,
    borderBottomLeftRadius: 12,
  },
  cornerBottomRight: {
    bottom: 0,
    right: 0,
    borderBottomWidth: 3,
    borderRightWidth: 3,
    borderBottomRightRadius: 12,
  },

  // Bottom Bar
  bottomBar: {
    alignItems: 'center',
    paddingBottom: Theme.spacing.xl,
  },
  captureContainer: {
    width: 72,
    height: 72,
    borderRadius: 36,
    borderWidth: 3,
    borderColor: 'rgba(255, 255, 255, 0.6)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Theme.spacing.m,
  },
  captureButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: Theme.colors.textInverse,
    alignItems: 'center',
    justifyContent: 'center',
  },
  captureButtonDisabled: {
    opacity: 0.7,
  },
  captureInner: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: Theme.colors.textInverse,
    borderWidth: 2,
    borderColor: 'rgba(0, 0, 0, 0.1)',
  },
  captureHint: {
    color: 'rgba(255, 255, 255, 0.7)',
    fontSize: 13,
  },

  // Permission Screen
  permissionContainer: {
    flex: 1,
  },
  permissionContent: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: Theme.spacing.xl,
  },
  permissionIcon: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Theme.spacing.l,
  },
  permissionTitle: {
    color: Theme.colors.textInverse,
    fontSize: 22,
    fontWeight: '600',
    textAlign: 'center',
    marginBottom: Theme.spacing.s,
  },
  permissionText: {
    color: 'rgba(255, 255, 255, 0.7)',
    fontSize: 15,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: Theme.spacing.xl,
    paddingHorizontal: Theme.spacing.l,
  },
  permissionButton: {
    backgroundColor: Theme.colors.textInverse,
    paddingVertical: 14,
    paddingHorizontal: 28,
    borderRadius: Theme.radius.m,
  },
  permissionButtonText: {
    color: '#000',
    fontSize: 16,
    fontWeight: '600',
  },
});
