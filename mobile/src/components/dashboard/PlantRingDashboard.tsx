import React from 'react';
import { View, StyleSheet, Image, Text, Platform } from 'react-native';
import { CircularProgress } from '../ui/CircularProgress';
import { Theme } from '../../theme';
import { BlurView } from 'expo-blur';
import { Droplet, Sun, Thermometer, Wind } from 'lucide-react-native';

interface PlantMetrics {
  soilMoisture: number; // 0-100
  light: number;        // 0-100 (normalized)
  temperature: number;  // 0-100 (normalized, or ideally mapped to 15-35 range)
  humidity: number;     // 0-100
}

interface PlantRingDashboardProps {
  imageUrl?: string;
  metrics: PlantMetrics;
  size?: number;
}

const METRIC_COLORS = {
  soil: '#4CC9F0', // Vivid Sky Blue
  light: '#F72585', // Fluorescent Pink (Cyberpunk-ish) -> No, let's go refined. 
                    // Let's use:
                    // Soil: Blue
                    // Light: Yellow/Orange
                    // Temp: Red/Pink
                    // Humidity: Teal
  
  // Refined Palette:
  // Soil (Water): #4FA3D1
  // Light (Sun): #FFB74D
  // Temp (Heat): #E57373
  // Humidity (Air): #81C784
};

const PALETTE = {
  soil: '#2DE2E6', // Neon Blue
  light: '#FF9100', // Neon Orange
  temp: '#F706CF', // Neon Pink
  humidity: '#D4FF00', // Volt Green
};

export function PlantRingDashboard({ imageUrl, metrics, size = 240 }: PlantRingDashboardProps) {
  const strokeWidth = 10;
  const gap = 5;
  
  // Calculate ring sizes
  // Outer to Inner
  const r1Size = size;
  const r2Size = r1Size - (strokeWidth * 2) - gap;
  const r3Size = r2Size - (strokeWidth * 2) - gap;
  const r4Size = r3Size - (strokeWidth * 2) - gap;
  
  const imageSize = r4Size - (strokeWidth * 2) - 20;

  return (
    <View style={[styles.container, { width: size, height: size }]}>
      
      {/* Ring 1: Soil Moisture (Outer) */}
      <View style={styles.ringContainer}>
        <CircularProgress
          size={r1Size}
          strokeWidth={strokeWidth}
          progress={metrics.soilMoisture}
          color={PALETTE.soil}
          trackColor={'rgba(255,255,255,0.1)'}
        />
      </View>

      {/* Ring 2: Light */}
      <View style={styles.ringContainer}>
        <CircularProgress
          size={r2Size}
          strokeWidth={strokeWidth}
          progress={metrics.light}
          color={PALETTE.light}
          trackColor={'rgba(255,255,255,0.1)'}
        />
      </View>

      {/* Ring 3: Temperature */}
      <View style={styles.ringContainer}>
        <CircularProgress
          size={r3Size}
          strokeWidth={strokeWidth}
          progress={metrics.temperature}
          color={PALETTE.temp}
          trackColor={'rgba(255,255,255,0.1)'}
        />
      </View>

      {/* Ring 4: Humidity (Inner) */}
      <View style={styles.ringContainer}>
        <CircularProgress
          size={r4Size}
          strokeWidth={strokeWidth}
          progress={metrics.humidity}
          color={PALETTE.humidity}
          trackColor={'rgba(255,255,255,0.1)'}
        />
      </View>

      {/* Center Image */}
      <View style={[styles.imageContainer, { width: imageSize, height: imageSize, borderRadius: imageSize / 2 }]}>
        {imageUrl ? (
          <Image source={{ uri: imageUrl }} style={styles.image} />
        ) : (
          <View style={[styles.placeholder, { backgroundColor: Theme.colors.bgMain }]}>
            <Text style={{ fontSize: 32 }}>🌿</Text>
          </View>
        )}
      </View>

      {/* Legend / Key (Optional - floating nearby or rely on parent to render legend) */}
      {/* We will leave legend to the parent to keep this component pure visualization */}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
    alignSelf: 'center',
  },
  ringContainer: {
    position: 'absolute',
    justifyContent: 'center',
    alignItems: 'center',
  },
  imageContainer: {
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.1)',
    ...Platform.select({
      web: { boxShadow: '0px 12px 24px rgba(0, 0, 0, 0.5)' },
      default: {
        shadowColor: "#000",
        shadowOffset: { width: 0, height: 12 },
        shadowOpacity: 0.5,
        shadowRadius: 20,
        elevation: 10,
      },
    }) as any,
    backgroundColor: Theme.colors.bgMain,
    zIndex: 10,
  },
  image: {
    width: '100%',
    height: '100%',
  },
  placeholder: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
