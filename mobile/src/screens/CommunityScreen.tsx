import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, Image, ActivityIndicator } from 'react-native';
import { Theme } from '../theme';
import { Users, Plus, ArrowRight } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { FadeInDown } from 'react-native-reanimated';
import { subscribeToCommunities, seedCommunitiesIfEmpty, Community, joinCommunity } from '../firebase';

export default function CommunityScreen() {
    const insets = useSafeAreaInsets();
    const [communities, setCommunities] = useState<Community[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
      // 1. Ensure we have data
      seedCommunitiesIfEmpty();

      // 2. Subscribe to real-time updates
      const unsubscribe = subscribeToCommunities((data) => {
        setCommunities(data);
        setLoading(false);
      });

      return () => unsubscribe();
    }, []);

    const handleJoin = async (id: string) => {
      try {
        await joinCommunity(id);
        // Ideally show a toast
      } catch (error) {
        console.error("Failed to join community:", error);
      }
    };

    const renderItem = ({ item, index }: { item: Community, index: number }) => (
        <Animated.View entering={FadeInDown.delay(index * 100).duration(600)}>
            <TouchableOpacity activeOpacity={0.9} style={styles.cardContainer}>
                <Image source={{ uri: item.imageUrl }} style={styles.cardImage} />
                <View style={styles.cardContent}>
                    <View>
                        <Text style={styles.cardTitle}>{item.name}</Text>
                        <View style={styles.cardMeta}>
                            <Users size={12} color="#888" />
                            <Text style={styles.metaText}>{item.members.toLocaleString()} MEMBERS</Text>
                        </View>
                    </View>
                    <TouchableOpacity 
                      style={styles.joinButton}
                      onPress={() => handleJoin(item.id)}
                    >
                        <ArrowRight size={20} color={Theme.colors.primary} />
                    </TouchableOpacity>
                </View>
            </TouchableOpacity>
        </Animated.View>
    );

  if (loading) {
    return (
      <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator size="large" color={Theme.colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={[styles.header, { paddingTop: insets.top + 20 }]}>
        <View>
            <View style={styles.badgeContainer}>
              <View style={styles.badgeLine} />
              <Text style={styles.badgeText}>SOCIAL</Text>
            </View>
            <Text style={styles.headerTitle}>CIRCLES</Text>
        </View>
        <TouchableOpacity style={styles.createButton}>
            <Plus size={24} color="#000" />
        </TouchableOpacity>
      </View>

      <FlatList
        data={communities}
        renderItem={renderItem}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.listContent}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <Text style={{ color: '#666', textAlign: 'center', marginTop: 40 }}>
            No communities found.
          </Text>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050A07', // Dark background
  },
  header: {
    paddingHorizontal: 24,
    paddingBottom: 32,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
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
  headerTitle: {
    fontSize: 42, // Massive
    fontWeight: '800',
    color: '#fff',
    letterSpacing: -2,
    lineHeight: 42,
  },
  createButton: {
    width: 48,
    height: 48,
    backgroundColor: Theme.colors.primary, // Volt Green
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 4,
  },
  listContent: {
    paddingHorizontal: 24,
    paddingBottom: 100,
    gap: 16,
  },
  cardContainer: {
    backgroundColor: '#0F1612',
    borderWidth: 1,
    borderColor: '#222',
    height: 120,
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 24,
  },
  cardImage: {
    width: 100,
    height: '100%',
    backgroundColor: '#222',
  },
  cardContent: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingLeft: 20,
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 8,
    letterSpacing: 0.5,
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  metaText: {
    fontSize: 12,
    color: '#888',
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  joinButton: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#333',
  },
});

