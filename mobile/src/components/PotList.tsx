import React from 'react';
import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Image } from 'react-native';
import { Plus, ChevronRight, Leaf } from 'lucide-react-native';
import { Theme } from '../theme';
import { Pot } from '../utils/types';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { FadeInDown } from 'react-native-reanimated';

interface PotListProps {
  pots: Pot[];
  onSelectPot: (pot: Pot) => void;
  onAddPot: () => void;
}

export default function PotList({ pots, onSelectPot, onAddPot }: PotListProps) {
  const insets = useSafeAreaInsets();

  return (
    <View style={styles.container}>
      <ScrollView 
        contentContainerStyle={[
          styles.scrollContent, 
          { paddingTop: insets.top + 20, paddingBottom: 120 }
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.subtitle}>{pots.length > 0 ? `${pots.length} ACTIVE` : 'START MONITORING'}</Text>
          <Text style={styles.title}>MY GARDEN</Text>
        </View>

        {pots.length === 0 ? (
          <Animated.View entering={FadeInDown.duration(400)} style={styles.emptyContainer}>
            <View style={styles.emptyIconContainer}>
              <Leaf size={40} color={Theme.colors.primary} />
            </View>
            <Text style={styles.emptyTitle}>NO POTS YET</Text>
            <Text style={styles.emptySubtitle}>
              Connect a GreenGenius Smart Pot to start monitoring your plants in real-time.
            </Text>
            
            <TouchableOpacity
              onPress={onAddPot}
              activeOpacity={0.8}
              style={styles.emptyButton}
            >
              <Plus size={20} color="#000" />
              <Text style={styles.emptyButtonText}>ADD SMART POT</Text>
            </TouchableOpacity>
          </Animated.View>
        ) : (
          <View style={styles.list}>
            {pots.map((pot, index) => (
              <Animated.View 
                key={pot.id}
                entering={FadeInDown.duration(400).delay(index * 100)}
              >
                <TouchableOpacity
                  onPress={() => onSelectPot(pot)}
                  activeOpacity={0.7}
                  style={styles.card}
                >
                    {/* Plant Image or Icon */}
                    <View style={styles.imageContainer}>
                      {pot.plantData?.imageUrl ? (
                        <Image source={{ uri: pot.plantData.imageUrl }} style={styles.image} />
                      ) : (
                        <View style={styles.imagePlaceholder}>
                          <Leaf size={24} color="#666" />
                        </View>
                      )}
                    </View>

                    {/* Pot Info */}
                    <View style={styles.info}>
                      <Text style={styles.potName}>{pot.name.toUpperCase()}</Text>
                      <View style={styles.statusRow}>
                        <View style={[
                          styles.statusDot, 
                          { backgroundColor: pot.plantData ? Theme.colors.statusGood : '#666' }
                        ]} />
                        <Text style={styles.plantName}>
                          {pot.plantData ? pot.plantData.name.toUpperCase() : 'NO PLANT ADDED'}
                        </Text>
                      </View>
                    </View>

                    {/* Chevron */}
                    <View style={styles.chevronContainer}>
                      <ChevronRight size={20} color={Theme.colors.primary} />
                    </View>
                </TouchableOpacity>
              </Animated.View>
            ))}
          </View>
        )}
      </ScrollView>

      {/* Floating Action Button */}
      {pots.length > 0 && (
        <TouchableOpacity
          onPress={onAddPot}
          activeOpacity={0.9}
          style={[styles.fab, { bottom: insets.bottom + 20 }]}
        >
          <Plus size={28} color="#000" />
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050A07', // Dark background
  },
  scrollContent: {
    paddingHorizontal: 24,
  },
  
  // Header
  header: {
    marginBottom: 40,
  },
  title: {
    fontSize: 42,
    fontWeight: '800', // Heavy bold
    color: '#fff',
    letterSpacing: -2,
    lineHeight: 42,
  },
  subtitle: {
    fontSize: 12,
    color: Theme.colors.primary,
    fontWeight: '700',
    letterSpacing: 2,
    marginBottom: 8,
  },
  
  // Empty State
  emptyContainer: {
    marginTop: 60,
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  emptyIconContainer: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(212, 255, 0, 0.05)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
    borderWidth: 1,
    borderColor: 'rgba(212, 255, 0, 0.1)',
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '800',
    color: '#fff',
    marginBottom: 12,
    letterSpacing: 1,
  },
  emptySubtitle: {
    fontSize: 14,
    color: '#888',
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 32,
  },
  emptyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Theme.colors.primary,
    paddingVertical: 16,
    paddingHorizontal: 32,
    gap: 8,
  },
  emptyButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#000',
    letterSpacing: 1,
  },
  
  // List
  list: {
    gap: 16,
  },
  card: {
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0F1612',
    borderWidth: 1,
    borderColor: '#222',
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
    marginLeft: 20,
  },
  potName: {
    fontSize: 16,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 6,
    letterSpacing: 0.5,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    marginRight: 8,
  },
  plantName: {
    fontSize: 12,
    color: '#888',
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  chevronContainer: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  
  // FAB
  fab: {
    position: 'absolute',
    right: 24,
    width: 64,
    height: 64,
    backgroundColor: Theme.colors.primary, // Square FAB
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#222',
  },
});
