import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Dimensions } from 'react-native';
import { Thermometer, Droplets, Sun, Droplet, Camera, Zap, Activity } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { FadeInDown, FadeIn } from 'react-native-reanimated';

import { Theme } from '../theme';
import { PlantData, SensorData, EnvironmentStatus, IdentificationState } from '../utils/types';
import { identifyPlant } from '../utils/api';

// New Components
import { PlantRingDashboard } from './dashboard/PlantRingDashboard';
import { MetricCard } from './dashboard/MetricCard';
import CameraView from './CameraView';
import PlantResult from './PlantResult';

const { width } = Dimensions.get('window');

interface DashboardProps {
  plantData: PlantData | null;
  sensorData: SensorData | null;
  envStatus: EnvironmentStatus[];
  onAddPlant: (plant: PlantData) => void;
  onBack: () => void;
}

// Colors for the Legend corresponding to PlantRingDashboard palette
const LEGEND_COLORS = {
  soil: '#2DE2E6', // Neon Blue
  light: '#FF9100', // Neon Orange
  temp: '#F706CF', // Neon Pink
  humidity: '#D4FF00', // Volt Green
};

export default function Dashboard({ plantData, sensorData, envStatus, onAddPlant, onBack }: DashboardProps) {
  const insets = useSafeAreaInsets();
  const [showCamera, setShowCamera] = React.useState(false);
  const [identificationState, setIdentificationState] = React.useState<IdentificationState>({ type: 'idle' });

  // Mock data normalization for the rings (0-100 scale)
  const metrics = {
    soilMoisture: sensorData?.soilMoisture ?? 0,
    light: Math.min(((sensorData?.light ?? 0) / 1000) * 100, 100), // Assuming 1000 lux is max for graph
    temperature: Math.min(((sensorData?.temperature ?? 0) / 40) * 100, 100), // Assuming 40C is max
    humidity: sensorData?.humidity ?? 0,
  };

  const handleCapture = async (base64: string) => {
    setShowCamera(false);
    setIdentificationState({ type: 'analyzing' });
    
    try {
      const result = await identifyPlant(base64);
      
      if (result.error || !result.identification) {
        setIdentificationState({ 
          type: 'error', 
          message: result.error || 'Unable to identify plant.' 
        });
        return;
      }

      const suggestions = result.suggestions || [];
      const confidence = result.confidence || (result.identification?.probability * 100) || 50;
      
      let results: PlantData[] = [];

      if (suggestions.length > 0) {
        results = suggestions.map((s: any) => ({
          id: s.id?.toString() || Date.now().toString(),
          name: s.name || 'Unknown Plant',
          scientificName: s.name,
          imageUrl: s.similar_images?.[0]?.url,
          compatible: true,
          confidence: (s.probability || 0) * 100,
        }));
      } else {
        const similarImages = result.identification?.similar_images || [];
        results = [{
          id: result.identification?.id?.toString() || Date.now().toString(),
          name: result.identification?.name || 'Unknown',
          scientificName: result.identification?.name,
          imageUrl: similarImages[0]?.url,
          compatible: true,
          confidence: confidence,
        }];
      }

      const topConfidence = results[0]?.confidence || 0;
      setIdentificationState({ 
        type: topConfidence >= 80 ? 'success' : 'low_confidence', 
        results 
      });

    } catch (error) {
      setIdentificationState({ 
        type: 'error', 
        message: 'Connection failed. Please check internet.' 
      });
    }
  };

  return (
    <View style={styles.container}>
      {/* Background - Dark Solid */}
      <View style={StyleSheet.absoluteFillObject}>
         <View style={{ flex: 1, backgroundColor: '#050A07' }} />
      </View>
      
      <ScrollView 
        contentContainerStyle={[
          styles.scrollContent, 
          { paddingTop: insets.top + Theme.spacing.s, paddingBottom: 100 }
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Animated.View entering={FadeInDown.duration(600).springify()}>
          <View style={styles.header}>
            <View>
              <Text style={styles.headerSubtitle}>MONITORING</Text>
              <Text style={styles.headerTitle}>{plantData ? plantData.name.toUpperCase() : "MY GARDEN"}</Text>
            </View>

            <TouchableOpacity 
              style={[styles.iconButton, !plantData && styles.iconButtonActive]}
              onPress={() => setShowCamera(true)}
            >
              <Camera size={24} color={Theme.colors.primary} />
            </TouchableOpacity>
          </View>
        </Animated.View>

        {/* Status / Error Message */}
        {identificationState.type === 'error' && (
          <View style={styles.errorBanner}>
            <Zap size={16} color={Theme.colors.statusBad} />
            <Text style={styles.errorText}>{identificationState.message}</Text>
          </View>
        )}

        {!plantData ? (
          /* Empty State / Identification Results */
          <View style={styles.emptyContainer}>
            {identificationState.type === 'idle' || identificationState.type === 'analyzing' ? (
              <View style={styles.welcomeCard}>
                <View style={styles.welcomeIcon}>
                  {identificationState.type === 'analyzing' ? (
                    <Activity size={48} color={Theme.colors.primary} style={{ opacity: 0.8 }} />
                  ) : (
                    <Camera size={48} color={Theme.colors.primary} />
                  )}
                </View>
                <Text style={styles.welcomeTitle}>
                  {identificationState.type === 'analyzing' ? 'ANALYZING SPECIES...' : 'ADD PLANT'}
                </Text>
                <Text style={styles.welcomeText}>
                  {identificationState.type === 'analyzing' 
                    ? 'Our AI is identifying your plant species.' 
                    : 'Scan your plant to begin monitoring.'}
                </Text>
                
                {identificationState.type === 'idle' && (
                  <TouchableOpacity 
                    style={styles.primaryButton}
                    onPress={() => setShowCamera(true)}
                  >
                    <Text style={styles.primaryButtonText}>SCAN PLANT</Text>
                  </TouchableOpacity>
                )}
              </View>
            ) : (identificationState.type === 'success' || identificationState.type === 'low_confidence') ? (
              /* Suggestion Results */
              <View style={styles.resultsContainer}>
                <Text style={styles.sectionTitle}>
                  {identificationState.type === 'success' ? 'MATCH FOUND' : 'POTENTIAL MATCHES'}
                </Text>
                {identificationState.results.map((plant, idx) => (
                  <Animated.View 
                    key={plant.id} 
                    entering={FadeInDown.delay(idx * 100).duration(400)}
                  >
                    <PlantResult 
                      plant={plant} 
                      onAdd={onAddPlant} 
                      showConfidence 
                    />
                  </Animated.View>
                ))}
                <TouchableOpacity 
                  style={styles.ghostButton}
                  onPress={() => setIdentificationState({ type: 'idle' })}
                >
                  <Text style={styles.ghostButtonText}>CANCEL</Text>
                </TouchableOpacity>
              </View>
            ) : null}
          </View>
        ) : (
          /* Main Dashboard Content */
          <View style={styles.dashboardContent}>
            
            {/* Hero Ring Visualization */}
            <Animated.View entering={FadeIn.duration(800)}>
              <View style={styles.heroContainer}>
                <PlantRingDashboard 
                  imageUrl={plantData.imageUrl} 
                  metrics={metrics}
                  size={Math.min(width * 0.6, 300)}
                />

                {/* Legend Chips for Rings */}
                <View style={styles.legendContainer}>
                  <View style={styles.legendItem}>
                    <View style={[styles.legendDot, { backgroundColor: LEGEND_COLORS.soil }]} />
                    <Text style={styles.legendText}>MOISTURE</Text>
                  </View>
                  <View style={styles.legendItem}>
                    <View style={[styles.legendDot, { backgroundColor: LEGEND_COLORS.light }]} />
                    <Text style={styles.legendText}>LIGHT</Text>
                  </View>
                  <View style={styles.legendItem}>
                    <View style={[styles.legendDot, { backgroundColor: LEGEND_COLORS.temp }]} />
                    <Text style={styles.legendText}>TEMP</Text>
                  </View>
                  <View style={styles.legendItem}>
                    <View style={[styles.legendDot, { backgroundColor: LEGEND_COLORS.humidity }]} />
                    <Text style={styles.legendText}>HUMIDITY</Text>
                  </View>
                </View>
              </View>
            </Animated.View>

            {/* Metrics Grid */}
            <View style={styles.metricsGrid}>
              <MetricCard 
                label="SOIL MOISTURE" 
                value={`${sensorData?.soilMoisture ?? '--'}%`} 
                unit=""
                icon={Droplet}
                color={LEGEND_COLORS.soil}
                status={envStatus.find(s => s.parameter === 'Soil Moisture')?.status}
              />
              <MetricCard 
                label="LIGHT LEVEL" 
                value={`${sensorData?.light ?? '--'}`} 
                unit="lux"
                icon={Sun}
                color={LEGEND_COLORS.light}
                status={envStatus.find(s => s.parameter === 'Light')?.status}
              />
              <MetricCard 
                label="TEMPERATURE" 
                value={`${sensorData?.temperature ?? '--'}`} 
                unit="°C"
                icon={Thermometer}
                color={LEGEND_COLORS.temp}
                status={envStatus.find(s => s.parameter === 'Temperature')?.status}
              />
              <MetricCard 
                label="HUMIDITY" 
                value={`${sensorData?.humidity ?? '--'}`} 
                unit="%"
                icon={Droplets}
                color={LEGEND_COLORS.humidity}
                status={envStatus.find(s => s.parameter === 'Humidity')?.status}
              />
            </View>

            {/* Insights Panel (Replacing simple text) */}
            <View style={styles.insightsCard}>
               <View style={styles.insightHeader}>
                  <View style={styles.insightIconBox}>
                     <Text style={styles.aiLabel}>AI</Text>
                  </View>
                  <Text style={styles.insightTitle}>LIVE INSIGHTS</Text>
               </View>
               <Text style={styles.insightText}>
                 Your {plantData.name} is in adequate condition. 
                 Soil moisture is stable. 
                 Consider increasing light exposure during afternoon hours.
               </Text>
            </View>

          </View>
        )}
      </ScrollView>

      {/* Camera Overlay */}
      {showCamera && (
        <CameraView 
          onCapture={handleCapture} 
          onClose={() => setShowCamera(false)} 
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Theme.colors.bgMain,
  },
  scrollContent: {
    paddingHorizontal: 24,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 40,
    marginTop: 12,
  },
  headerSubtitle: {
    fontSize: 12,
    color: Theme.colors.primary,
    fontWeight: '700',
    letterSpacing: 2,
    marginBottom: 6,
  },
  headerTitle: {
    fontSize: 36,
    fontWeight: '800',
    color: '#fff',
    letterSpacing: -1.5,
    lineHeight: 36,
  },
  iconButton: {
    width: 52,
    height: 52,
    borderRadius: 14,
    backgroundColor: '#0F1612',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  iconButtonActive: {
    backgroundColor: Theme.colors.primary,
    borderColor: Theme.colors.primary,
  },
  errorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(247, 6, 207, 0.08)',
    padding: 16,
    borderRadius: 12,
    marginBottom: 32,
    borderWidth: 1,
    borderColor: 'rgba(247, 6, 207, 0.3)',
  },
  errorText: {
    marginLeft: 12,
    color: Theme.colors.statusBad,
    fontSize: 14,
    fontWeight: '600',
  },
  emptyContainer: {
    alignItems: 'center',
    marginTop: 20,
  },
  welcomeCard: {
    width: '100%',
    backgroundColor: '#0F1612',
    borderRadius: 32,
    padding: 40,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.03)',
  },
  welcomeIcon: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(212, 255, 0, 0.03)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
    borderWidth: 1,
    borderColor: 'rgba(212, 255, 0, 0.1)',
  },
  welcomeTitle: {
    fontSize: 24,
    fontWeight: '800',
    color: '#fff',
    marginBottom: 12,
    letterSpacing: -0.5,
  },
  welcomeText: {
    fontSize: 14,
    color: Theme.colors.textSecondary,
    textAlign: 'center',
    marginBottom: 32,
    lineHeight: 22,
    paddingHorizontal: 10,
  },
  primaryButton: {
    backgroundColor: Theme.colors.primary,
    height: 60,
    borderRadius: 30,
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    ...Platform.select({
        web: { boxShadow: '0px 8px 16px rgba(212, 255, 0, 0.2)' },
        default: {
            shadowColor: Theme.colors.primary,
            shadowOffset: { width: 0, height: 8 },
            shadowOpacity: 0.2,
            shadowRadius: 16,
            elevation: 8,
        }
    }) as any,
  },
  primaryButtonText: {
    color: '#000',
    fontSize: 15,
    fontWeight: '800',
    letterSpacing: 1,
  },
  resultsContainer: {
    width: '100%',
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '800',
    color: Theme.colors.primary,
    marginBottom: 16,
    letterSpacing: 2,
  },
  ghostButton: {
    marginTop: 24,
    padding: 16,
    alignItems: 'center',
  },
  ghostButtonText: {
    color: Theme.colors.textTertiary,
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 1,
  },
  dashboardContent: {
    gap: 40,
  },
  heroContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
  },
  legendContainer: {
    flexDirection: 'row',
    marginTop: 32,
    flexWrap: 'wrap',
    gap: 12,
    justifyContent: 'center',
  },
  legendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(255,255,255,0.03)',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  legendDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  legendText: {
    fontSize: 10,
    color: Theme.colors.textSecondary,
    fontWeight: '800',
    letterSpacing: 1,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
  },
  insightsCard: {
    backgroundColor: '#0F1612',
    padding: 24,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.03)',
    overflow: 'hidden',
  },
  insightHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 12,
  },
  insightIconBox: {
    backgroundColor: Theme.colors.primary,
    width: 28,
    height: 18,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  aiLabel: {
    fontSize: 10,
    fontWeight: '900',
    color: '#000',
  },
  insightTitle: {
    fontSize: 14,
    fontWeight: '800',
    color: '#fff',
    letterSpacing: 1.5,
  },
  insightText: {
    color: 'rgba(255,255,255,0.7)',
    lineHeight: 24,
    fontSize: 14,
    fontWeight: '500',
  },
});
