import React, { useState } from 'react';
import { useEffect } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, Image, ActivityIndicator, TextInput, Modal, KeyboardAvoidingView, Platform, TouchableWithoutFeedback, Keyboard, Alert } from 'react-native';
import { Theme } from '../theme';
import { Users, Plus, ArrowRight, Search, Lock, Key } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import Animated, { FadeInDown } from 'react-native-reanimated';
import { subscribeToCommunities, Community, joinCommunity, wipeAllCommunities, getCommunities } from '../firebase';
import { BlurView } from 'expo-blur';

export default function CommunityScreen() {
    const navigation = useNavigation<any>();
    const insets = useSafeAreaInsets();
    const [communities, setCommunities] = useState<Community[]>([]);
    const [filteredCommunities, setFilteredCommunities] = useState<Community[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');
    
    // Join Code Modal
    const [isJoinModalVisible, setIsJoinModalVisible] = useState(false);
    const [joinCodeInput, setJoinCodeInput] = useState('');
    const [joining, setJoining] = useState(false);

    useEffect(() => {
      const initSubscribe = async () => {
        setLoading(true);
        const unsubscribe = subscribeToCommunities((data) => {
          setCommunities(data);
          setLoading(false);
        });
        return unsubscribe;
      };

      let unsubFunc: (() => void) | undefined;
      initSubscribe().then(unsub => {
        unsubFunc = unsub;
      });

      return () => {
        if (unsubFunc) unsubFunc();
      };
    }, []);

    useEffect(() => {
        if (!searchQuery.trim()) {
            setFilteredCommunities(communities.filter(c => !c.isPrivate));
            return;
        }

        const query = searchQuery.toLowerCase().trim();
        const filtered = communities.filter(c => {
            if (!c.isPrivate && c.name.toLowerCase().includes(query)) return true;
            return false;
        });
        setFilteredCommunities(filtered);
    }, [searchQuery, communities]);

    const handleJoin = async (id: string) => {
      try {
        await joinCommunity(id);
        Alert.alert("Success", "You have joined the group!");
      } catch (error) {
        console.error("Failed to join community:", error);
      }
    };
    
    const handleJoinByCode = async () => {
        if (!joinCodeInput.trim()) return;
        setJoining(true);
        
        // Find community with this code
        // In a real app, use a query. For now, filter client side list (since we subscribe to all).
        // Wait, 'subscribeToCommunities' returns ALL. If RLS is enabled, we might not see private ones?
        // Assuming we fetch all for now.
        const target = communities.find(c => c.joinCode === joinCodeInput.trim());
        
        if (target) {
            await handleJoin(target.id);
            setJoining(false);
            setIsJoinModalVisible(false);
            setJoinCodeInput('');
            navigation.navigate('PlantGroup', { groupId: target.id, name: target.name });
        } else {
            setJoining(false);
            Alert.alert("Invalid Code", "No group found with that join code.");
        }
    };

    const renderItem = ({ item, index }: { item: Community, index: number }) => (
        <Animated.View entering={FadeInDown.delay(index * 100).duration(600)}>
            <TouchableOpacity 
                activeOpacity={0.9} 
                style={styles.cardContainer}
                onPress={() => navigation.navigate('PlantGroup', { groupId: item.id, name: item.name })}
            >
                <Image source={{ uri: item.imageUrl }} style={styles.cardImage} />
                <View style={styles.cardContent}>
                    <View>
                        <Text style={styles.cardTitle}>{item.name}</Text>
                        <View style={styles.cardMeta}>
                            <Users size={12} color="#888" />
                            <Text style={styles.metaText}>{item.members.toLocaleString()} MEMBERS</Text>
                            {item.isPrivate && (
                                <View style={styles.privateTag}>
                                    <Lock size={10} color={Theme.colors.primary} />
                                    <Text style={styles.privateText}>PRIVATE</Text>
                                </View>
                            )}
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
        <View style={{ flexDirection: 'row', gap: 12 }}>
            <TouchableOpacity 
                style={styles.createButton}
                onPress={() => setIsJoinModalVisible(true)}
            >
                <Key size={24} color="#000" />
            </TouchableOpacity>
            <TouchableOpacity 
                style={styles.createButton}
                onPress={() => navigation.navigate('CreateCommunity')}
            >
                <Plus size={24} color="#000" />
            </TouchableOpacity>
        </View>
      </View>

      <View style={styles.searchContainer}>
        <Search size={20} color="#666" style={styles.searchIcon} />
        <TextInput 
            style={styles.searchInput}
            placeholder="Search groups..."
            placeholderTextColor="#666"
            value={searchQuery}
            onChangeText={setSearchQuery}
        />
      </View>

      <FlatList
        data={filteredCommunities}
        renderItem={renderItem}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.listContent}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <View style={styles.emptyState}>
              <Text style={styles.emptyText}>
                  {searchQuery ? "No communities found." : "No communities yet. Create one!"}
              </Text>
          </View>
        }
      />
      
      {/* Join Code Modal */}
      <Modal
        visible={isJoinModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setIsJoinModalVisible(false)}
      >
        <TouchableOpacity 
            style={styles.modalOverlay} 
            activeOpacity={1} 
            onPress={() => setIsJoinModalVisible(false)}
        >
            <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
                <TouchableWithoutFeedback>
                    <View style={styles.modalContent}>
                        <Text style={styles.modalTitle}>Enter Join Code</Text>
                        <Text style={styles.modalSubtitle}>Enter the invite code to join a private group.</Text>
                        
                        <TextInput
                            style={styles.modalInput}
                            placeholder="X7Y9Z2"
                            placeholderTextColor="#666"
                            value={joinCodeInput}
                            onChangeText={txt => setJoinCodeInput(txt.toUpperCase())}
                            maxLength={8}
                        />
                        
                        <TouchableOpacity 
                            style={styles.modalButton}
                            onPress={handleJoinByCode}
                            disabled={joining}
                        >
                            {joining ? <ActivityIndicator color="#000" /> : <Text style={styles.modalButtonText}>Join Group</Text>}
                        </TouchableOpacity>
                    </View>
                </TouchableWithoutFeedback>
            </KeyboardAvoidingView>
        </TouchableOpacity>
      </Modal>

    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Theme.colors.bgMain,
  },
  header: {
    paddingHorizontal: 24,
    paddingBottom: 24,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
    gap: 8,
  },
  badgeLine: {
    width: 20,
    height: 2,
    backgroundColor: Theme.colors.primary,
  },
  badgeText: {
    color: Theme.colors.primary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 2,
  },
  headerTitle: {
    fontSize: 32,
    fontWeight: '800',
    color: Theme.colors.textPrimary,
    letterSpacing: -1,
    lineHeight: 36,
  },
  createButton: {
    width: 44,
    height: 44,
    backgroundColor: Theme.colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 12,
  },
  listContent: {
    paddingHorizontal: 24,
    paddingBottom: 120,
    gap: 16,
  },
  cardContainer: {
    backgroundColor: Theme.colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    height: 110,
    flexDirection: 'row',
    alignItems: 'center',
    overflow: 'hidden',
  },
  cardImage: {
    width: 90,
    height: '100%',
    backgroundColor: '#111',
  },
  cardContent: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: Theme.colors.textPrimary,
    marginBottom: 4,
    letterSpacing: 0.2,
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  metaText: {
    fontSize: 11,
    color: Theme.colors.textSecondary,
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  joinButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  searchContainer: {
    marginHorizontal: 24,
    marginBottom: 20,
    height: 48,
    backgroundColor: Theme.colors.surface,
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  searchIcon: {
    marginRight: 12,
  },
  searchInput: {
    flex: 1,
    color: Theme.colors.textPrimary,
    fontSize: 14,
    height: '100%',
  },
  emptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 60,
    paddingHorizontal: 40,
  },
  emptyText: {
    color: Theme.colors.textTertiary,
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 20,
  },
  privateTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'rgba(212, 255, 0, 0.1)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginLeft: 8,
  },
  privateText: {
    color: Theme.colors.primary,
    fontSize: 10,
    fontWeight: '700',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.85)',
    justifyContent: 'center',
    padding: 24,
  },
  modalContent: {
    backgroundColor: '#0F1612',
    borderRadius: 24,
    padding: 32,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  modalTitle: {
    color: Theme.colors.textPrimary,
    fontSize: 22,
    fontWeight: '800',
    marginBottom: 8,
    textAlign: 'center',
  },
  modalSubtitle: {
    color: Theme.colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 32,
    lineHeight: 20,
  },
  modalInput: {
    backgroundColor: '#000',
    borderRadius: 16,
    padding: 16,
    color: Theme.colors.textPrimary,
    fontSize: 24,
    textAlign: 'center',
    letterSpacing: 4,
    borderWidth: 1,
    borderColor: '#333',
    marginBottom: 32,
    fontWeight: '700',
  },
  modalButton: {
    backgroundColor: Theme.colors.primary,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modalButtonText: {
    color: '#000',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
});

