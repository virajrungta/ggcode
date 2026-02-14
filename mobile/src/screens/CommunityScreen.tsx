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
      const initWipeAndSubscribe = async () => {
        // WIPE ALL DATA (As requested to remove placeholders)
        await wipeAllCommunities();
        
        // Then start subscription
        const unsubscribe = subscribeToCommunities((data) => {
          setCommunities(data);
          setLoading(false);
        });
        return unsubscribe;
      };

      let unsubFunc: (() => void) | undefined;
      initWipeAndSubscribe().then(unsub => {
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
  searchContainer: {
    marginHorizontal: 24,
    marginBottom: 24,
    height: 50,
    backgroundColor: '#0F1612',
    borderRadius: 25,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    borderWidth: 1,
    borderColor: '#222',
  },
  searchIcon: {
    marginRight: 12,
  },
  searchInput: {
    flex: 1,
    color: '#fff',
    fontSize: 16,
    height: '100%',
  },
  emptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 60,
  },
  emptyText: {
    color: '#666',
    fontSize: 16,
    textAlign: 'center',
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
    backgroundColor: 'rgba(0,0,0,0.8)',
    justifyContent: 'center',
    padding: 24,
  },
  modalContent: {
    backgroundColor: '#1A1A1A',
    borderRadius: 20,
    padding: 24,
    borderWidth: 1,
    borderColor: '#333',
  },
  modalTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 8,
    textAlign: 'center',
  },
  modalSubtitle: {
    color: '#888',
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 24,
  },
  modalInput: {
    backgroundColor: '#000',
    borderRadius: 12,
    padding: 16,
    color: '#fff',
    fontSize: 18,
    textAlign: 'center',
    letterSpacing: 2,
    borderWidth: 1,
    borderColor: '#333',
    marginBottom: 24,
  },
  modalButton: {
    backgroundColor: Theme.colors.primary,
    height: 50,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modalButtonText: {
    color: '#000',
    fontSize: 16,
    fontWeight: '700',
  },
});

