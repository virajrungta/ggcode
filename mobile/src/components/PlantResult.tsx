import React from 'react';
import { View, Text, StyleSheet, Image, TouchableOpacity } from 'react-native';
import { Plus, Leaf, AlertCircle } from 'lucide-react-native';
import { Theme } from '../theme';
import { PlantData } from '../utils/types';
import Animated, { FadeIn } from 'react-native-reanimated';

interface PlantResultProps {
  plant: PlantData;
  onAdd: (plant: PlantData) => void;
  showConfidence?: boolean;
}

export default function PlantResult({ plant, onAdd, showConfidence = false }: PlantResultProps) {
  const confidence = plant.confidence || 0;
  
  const getConfidenceLabel = () => {
    if (confidence >= 80) return 'HIGH MATCH';
    if (confidence >= 50) return 'MEDIUM';
    return 'LOW MATCH';
  };
  
  const getConfidenceColor = () => {
    if (confidence >= 80) return Theme.colors.statusGood;
    if (confidence >= 50) return Theme.colors.statusWarning;
    return Theme.colors.statusBad;
  };

  return (
    <Animated.View entering={FadeIn.duration(300)}>
      <View style={styles.container}>
        {/* Plant Image */}
        <View style={styles.imageContainer}>
          {plant.imageUrl ? (
            <Image source={{ uri: plant.imageUrl }} style={styles.image} />
          ) : (
            <View style={styles.imagePlaceholder}>
              <Leaf size={24} color="#666" />
            </View>
          )}
        </View>
        
        {/* Plant Info */}
        <View style={styles.info}>
          <Text style={styles.name} numberOfLines={1}>{plant.name.toUpperCase()}</Text>
          <Text style={styles.scientific} numberOfLines={1}>{plant.scientificName}</Text>
          
          {/* Confidence Indicator */}
          {showConfidence && confidence > 0 && (
            <View style={styles.confidenceRow}>
              <View style={[styles.confidenceBar, { width: `${confidence}%`, backgroundColor: getConfidenceColor() }]} />
              <Text style={[styles.confidenceText, { color: getConfidenceColor() }]}>
                {Math.round(confidence)}% • {getConfidenceLabel()}
              </Text>
            </View>
          )}
          
          {/* Incompatible Warning */}
          {!plant.compatible && (
            <View style={styles.warningBadge}>
              <AlertCircle size={12} color={Theme.colors.statusWarning} />
              <Text style={styles.warningText}>LIMITED SUPPORT</Text>
            </View>
          )}
        </View>

        {/* Add Button */}
        <TouchableOpacity
          onPress={() => onAdd(plant)}
          disabled={!plant.compatible}
          activeOpacity={0.7}
          style={[
            styles.addButton,
            !plant.compatible && styles.addButtonDisabled
          ]}
        >
          <Plus size={24} color="#000" />
        </TouchableOpacity>
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#0F1612',
    borderWidth: 1,
    borderColor: '#222',
    gap: 16,
  },
  imageContainer: {
    width: 64,
    height: 64,
    backgroundColor: '#000',
    borderWidth: 1,
    borderColor: '#333',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  imagePlaceholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#111',
  },
  info: {
    flex: 1,
    gap: 4,
  },
  name: {
    fontSize: 14,
    fontWeight: '800',
    color: '#fff',
    letterSpacing: 0.5,
  },
  scientific: {
    fontSize: 12,
    color: '#888',
    fontStyle: 'italic',
  },
  confidenceRow: {
    marginTop: 8,
  },
  confidenceBar: {
    height: 2,
    borderRadius: 0,
    marginBottom: 4,
    maxWidth: '100%',
  },
  confidenceText: {
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  warningBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 6,
    gap: 4,
  },
  warningText: {
    fontSize: 10,
    color: Theme.colors.statusWarning,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  addButton: {
    width: 48,
    height: 48,
    backgroundColor: Theme.colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addButtonDisabled: {
    backgroundColor: '#222',
  },
});
