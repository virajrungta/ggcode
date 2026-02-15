import React, { useState, useRef } from 'react';
import { useEffect } from 'react';
import { 
  View, Text, StyleSheet, FlatList, TouchableOpacity, Image, 
  TextInput, Modal, KeyboardAvoidingView, Platform, ScrollView, ActivityIndicator 
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, MoreHorizontal, Heart, MessageCircle, Share2, Send, Image as ImageIcon, X } from 'lucide-react-native';
import { Theme } from '../../theme';
import { GlassCard } from '../../components/ui/GlassCard';
import { BlurView } from 'expo-blur';

// --- Types ---
interface Comment {
  id: string;
  user: {
    name: string;
    avatar: string; // URL
  };
  content: string;
  timestamp: string;
}

interface Post {
  id: string;
  user: {
    name: string;
    avatar: string;
    role?: 'Admin' | 'Expert' | 'Member';
  };
  content: string;
  image?: string; // Optional image URL
  likes: number;
  comments: Comment[];
  timestamp: string;
  isLiked?: boolean;
}

import { getCommunity, Community } from '../../firebase/firestoreService';

export default function PlantGroupScreen({ navigation, route }: any) {
    const insets = useSafeAreaInsets();
    const { groupId, name: paramName } = route.params || {};
    
    const [groupData, setGroupData] = useState<Community | null>(null);
    const [posts, setPosts] = useState<Post[]>([]); // New groups start empty
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (groupId) {
            getCommunity(groupId).then(data => {
                if (data) setGroupData(data);
                setLoading(false);
            });
        }
    }, [groupId]);
    const [newPostText, setNewPostText] = useState('');
    const [isPostModalVisible, setIsPostModalVisible] = useState(false);
    
    // Commenting state
    const [activeCommentPostId, setActiveCommentPostId] = useState<string | null>(null);
    const [newCommentText, setNewCommentText] = useState('');

    const handleBack = () => navigation.goBack();

    if (loading || !groupData) {
        return (
            <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
                <ActivityIndicator size="large" color={Theme.colors.primary} />
            </View>
        );
    }

    const handleCreatePost = () => {
        if (!newPostText.trim()) return;
        
        const newPost: Post = {
            id: Date.now().toString(),
            user: {
                name: 'You',
                avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=100&q=80', // Current user avatar mockup
                role: 'Member'
            },
            content: newPostText,
            likes: 0,
            comments: [],
            timestamp: 'Just now'
        };

        setPosts([newPost, ...posts]);
        setNewPostText('');
        setIsPostModalVisible(false);
    };

    const handleLike = (postId: string) => {
        setPosts(posts.map(p => {
            if (p.id === postId) {
                return { 
                    ...p, 
                    likes: p.isLiked ? p.likes - 1 : p.likes + 1, 
                    isLiked: !p.isLiked 
                };
            }
            return p;
        }));
    };

    const handleAddComment = (postId: string) => {
        if (!newCommentText.trim()) return;

        setPosts(posts.map(p => {
            if (p.id === postId) {
                return {
                    ...p,
                    comments: [
                        ...p.comments,
                        {
                            id: Date.now().toString(),
                            user: { name: 'You', avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=100&q=80' },
                            content: newCommentText,
                            timestamp: 'Just now'
                        }
                    ]
                };
            }
            return p;
        }));
        setNewCommentText('');
        // Don't close immediately, allow rapid commenting
    };

    const renderHeader = () => {
        if (!groupData) return null;
        return (
        <View style={styles.headerContainer}>
            <View style={styles.coverImageContainer}>
                <Image source={{ uri: groupData.imageUrl }} style={styles.coverImage} />
                <View style={styles.coverOverlay} />
                <View style={[styles.navBar, { paddingTop: insets.top }]}>
                    <TouchableOpacity onPress={handleBack} style={styles.iconButtonBlur}>
                        <BlurView intensity={30} style={StyleSheet.absoluteFill} />
                        <ArrowLeft color="#fff" size={24} />
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.iconButtonBlur}>
                        <BlurView intensity={30} style={StyleSheet.absoluteFill} />
                        <MoreHorizontal color="#fff" size={24} />
                    </TouchableOpacity>
                </View>

                <View style={styles.groupInfoContainer}>
                    <View style={styles.tagsRow}>
                        {groupData.tags.map(tag => (
                            <View key={tag} style={styles.tagBadge}>
                                <Text style={styles.tagText}>{tag.toUpperCase()}</Text>
                            </View>
                        ))}
                    </View>
                    <Text style={styles.groupName}>{groupData.name}</Text>
                    <Text style={styles.groupMembers}>{groupData.members.toLocaleString()} members • 24 online</Text>
                </View>
            </View>

            <View style={styles.descriptionContainer}>
                <Text style={styles.descriptionText}>{groupData.description}</Text>
            </View>

            {/* Create Post Trigger */}
            <TouchableOpacity 
                activeOpacity={0.8}
                style={styles.createPostTrigger}
                onPress={() => setIsPostModalVisible(true)}
            >
                <Image 
                    source={{ uri: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=100&q=80' }} 
                    style={styles.triggerAvatar} 
                />
                <Text style={styles.triggerText}>Share something with the group...</Text>
                <ImageIcon size={20} color={Theme.colors.primary} />
            </TouchableOpacity>

            <View style={styles.feedTabs}>
                <Text style={[styles.tabText, styles.activeTab]}>Discussion</Text>
                <Text style={styles.tabText}>Photos</Text>
                <Text style={styles.tabText}>Q&A</Text>
            </View>
        </View>
        );
    };

    const renderPost = ({ item }: { item: Post }) => (
        <GlassCard style={styles.postCard} intensity={10}>
            {/* Post Header */}
            <View style={styles.postHeader}>
                <Image source={{ uri: item.user.avatar }} style={styles.userAvatar} />
                <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                        <Text style={styles.userName}>{item.user.name}</Text>
                        {item.user.role && (
                            <View style={[styles.roleBadge, item.user.role === 'Admin' ? { backgroundColor: Theme.colors.primary } : {}]}>
                                <Text style={[styles.roleText, item.user.role === 'Admin' ? { color: '#000' } : {}]}>
                                    {item.user.role}
                                </Text>
                            </View>
                        )}
                    </View>
                    <Text style={styles.timestamp}>{item.timestamp}</Text>
                </View>
                <TouchableOpacity>
                    <MoreHorizontal size={20} color="#666" />
                </TouchableOpacity>
            </View>

            {/* Content */}
            <Text style={styles.postContent}>{item.content}</Text>
            
            {item.image && (
                <Image source={{ uri: item.image }} style={styles.postImage} resizeMode="cover" />
            )}

            {/* Action Bar */}
            <View style={styles.actionBar}>
                <TouchableOpacity style={styles.actionButton} onPress={() => handleLike(item.id)}>
                    <Heart 
                        size={22} 
                        color={item.isLiked ? Theme.colors.statusBad : "#888"} 
                        fill={item.isLiked ? Theme.colors.statusBad : "transparent"} 
                    />
                    <Text style={[styles.actionText, item.isLiked && { color: Theme.colors.statusBad }]}>
                        {item.likes}
                    </Text>
                </TouchableOpacity>

                <TouchableOpacity 
                    style={styles.actionButton} 
                    onPress={() => setActiveCommentPostId(item.id === activeCommentPostId ? null : item.id)}
                >
                    <MessageCircle size={22} color="#888" />
                    <Text style={styles.actionText}>{item.comments.length}</Text>
                </TouchableOpacity>

                <TouchableOpacity style={styles.actionButton}>
                    <Share2 size={22} color="#888" />
                </TouchableOpacity>
            </View>

            {/* Comments Section (Expandable) */}
            {activeCommentPostId === item.id && (
                <View style={styles.commentSection}>
                    {item.comments.map(comment => (
                        <View key={comment.id} style={styles.commentRow}>
                            <Image source={{ uri: comment.user.avatar }} style={styles.commentAvatar} />
                            <View style={styles.commentBubble}>
                                <Text style={styles.commentUser}>{comment.user.name}</Text>
                                <Text style={styles.commentText}>{comment.content}</Text>
                            </View>
                        </View>
                    ))}
                    
                    {/* Add Comment Input */}
                    <View style={styles.addCommentRow}>
                         <Image 
                            source={{ uri: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=100&q=80' }} 
                            style={styles.commentAvatarSmall} 
                        />
                        <TextInput 
                            style={styles.commentInput}
                            placeholder="Add a comment..."
                            placeholderTextColor="#666"
                            value={newCommentText}
                            onChangeText={setNewCommentText}
                            onSubmitEditing={() => handleAddComment(item.id)}
                        />
                        {newCommentText.length > 0 && (
                            <TouchableOpacity onPress={() => handleAddComment(item.id)}>
                                <Send size={16} color={Theme.colors.primary} />
                            </TouchableOpacity>
                        )}
                    </View>
                </View>
            )}
        </GlassCard>
    );

    return (
        <View style={styles.container}>
            <FlatList
                data={posts}
                renderItem={renderPost}
                keyExtractor={item => item.id}
                ListHeaderComponent={renderHeader}
                contentContainerStyle={styles.listContent}
                showsVerticalScrollIndicator={false}
                ListEmptyComponent={
                    <View style={{ padding: 40, alignItems: 'center' }}>
                        <Text style={{ color: '#666', textAlign: 'center', fontSize: 16 }}>
                            No posts yet. Be the first to share something!
                        </Text>
                    </View>
                }
            />

            {/* Create Post Modal */}
            <Modal
                visible={isPostModalVisible}
                animationType="slide"
                transparent={true}
                onRequestClose={() => setIsPostModalVisible(false)}
            >
                <KeyboardAvoidingView 
                    behavior={Platform.OS === 'ios' ? 'padding' : 'height'} 
                    style={styles.modalContainer}
                >
                    <BlurView intensity={100} tint="dark" style={styles.modalContent}>
                        <View style={styles.modalHeader}>
                            <TouchableOpacity onPress={() => setIsPostModalVisible(false)}>
                                <X color="#fff" size={24} />
                            </TouchableOpacity>
                            <Text style={styles.modalTitle}>Create Post</Text>
                            <TouchableOpacity 
                                disabled={!newPostText.trim()} 
                                onPress={handleCreatePost}
                                style={[styles.postButton, !newPostText.trim() && { opacity: 0.5 }]}
                            >
                                <Text style={styles.postButtonText}>Post</Text>
                            </TouchableOpacity>
                        </View>
                        
                        <TextInput
                            style={styles.postInput}
                            placeholder="What's going on in your jungle?"
                            placeholderTextColor="#666"
                            multiline
                            autoFocus
                            value={newPostText}
                            onChangeText={setNewPostText}
                        />
                        
                        {/* Fake attachment bar */}
                        <View style={styles.attachmentBar}>
                            <TouchableOpacity style={styles.attachButton}>
                                <ImageIcon color={Theme.colors.primary} size={24} />
                                <Text style={styles.attachText}>Photo</Text>
                            </TouchableOpacity>
                        </View>
                    </BlurView>
                </KeyboardAvoidingView>
            </Modal>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: Theme.colors.bgMain,
    },
    listContent: {
        paddingBottom: 100,
    },
    headerContainer: {
        marginBottom: 16,
    },
    coverImageContainer: {
        height: 300,
        width: '100%',
        position: 'relative',
    },
    coverImage: {
        width: '100%',
        height: '100%',
    },
    coverOverlay: {
        ...StyleSheet.absoluteFillObject,
        backgroundColor: 'rgba(0,0,0,0.4)',
    },
    navBar: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        paddingHorizontal: 16,
        paddingTop: 10,
    },
    iconButtonBlur: {
        width: 44, 
        height: 44,
        borderRadius: 12,
        overflow: 'hidden',
        alignItems: 'center',
        justifyContent: 'center',
    },
    groupInfoContainer: {
        position: 'absolute',
        bottom: 24,
        left: 24,
        right: 24,
    },
    tagsRow: {
        flexDirection: 'row',
        gap: 8,
        marginBottom: 8,
    },
    tagBadge: {
        backgroundColor: Theme.colors.primary,
        paddingHorizontal: 10,
        paddingVertical: 4,
        borderRadius: 6,
    },
    tagText: {
        color: '#000',
        fontSize: 10,
        fontWeight: '800',
        letterSpacing: 1,
    },
    groupName: {
        fontSize: 32,
        fontWeight: '800',
        color: Theme.colors.textPrimary,
        ...Platform.select({
            ios: {
                textShadowColor: 'rgba(0,0,0,0.5)',
                textShadowOffset: { width: 0, height: 2 },
                textShadowRadius: 8,
            },
            android: {
                textShadowColor: 'rgba(0,0,0,0.5)',
                textShadowOffset: { width: 0, height: 2 },
                textShadowRadius: 8,
            },
            web: {
                textShadow: '0px 2px 8px rgba(0,0,0,0.5)',
            }
        } as any),
        marginBottom: 4,
        letterSpacing: -0.5,
    },
    groupMembers: {
        color: 'rgba(255,255,255,0.7)',
        fontSize: 13,
        fontWeight: '600',
        letterSpacing: 0.5,
    },
    descriptionContainer: {
        padding: 24,
        backgroundColor: Theme.colors.surface,
        borderBottomWidth: 1,
        borderBottomColor: 'rgba(255,255,255,0.05)',
    },
    descriptionText: {
        color: Theme.colors.textSecondary,
        fontSize: 14,
        lineHeight: 22,
    },
    createPostTrigger: {
        backgroundColor: '#0A0F0C',
        marginHorizontal: 16,
        marginTop: 16,
        padding: 16,
        borderRadius: 16,
        flexDirection: 'row',
        alignItems: 'center',
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.05)',
    },
    triggerAvatar: {
        width: 36, 
        height: 36,
        borderRadius: 18,
        marginRight: 12,
    },
    triggerText: {
        flex: 1,
        color: Theme.colors.textTertiary,
        fontSize: 14,
    },
    feedTabs: {
        flexDirection: 'row',
        marginHorizontal: 16,
        marginTop: 24,
        borderBottomWidth: 1,
        borderBottomColor: 'rgba(255,255,255,0.1)',
        gap: 24,
        paddingHorizontal: 8,
    },
    tabText: {
        fontSize: 15,
        color: Theme.colors.textTertiary,
        paddingBottom: 12,
        fontWeight: '700',
        letterSpacing: 0.5,
    },
    activeTab: {
        color: Theme.colors.primary,
        borderBottomWidth: 2,
        borderBottomColor: Theme.colors.primary,
    },
    
    // Post Card Styles
    postCard: {
        marginHorizontal: 16,
        marginTop: 16,
        padding: 16,
        borderRadius: 20,
    },
    postHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 16,
    },
    userAvatar: {
        width: 44,
        height: 44,
        borderRadius: 22,
        marginRight: 12,
    },
    userName: {
        color: Theme.colors.textPrimary,
        fontWeight: '700',
        fontSize: 15,
    },
    roleBadge: {
        backgroundColor: 'rgba(255,255,255,0.1)',
        paddingHorizontal: 8,
        paddingVertical: 2,
        borderRadius: 6,
    },
    roleText: {
        fontSize: 10,
        color: Theme.colors.textSecondary,
        fontWeight: '700',
        textTransform: 'uppercase',
    },
    timestamp: {
        color: Theme.colors.textTertiary,
        fontSize: 12,
        marginTop: 2,
    },
    postContent: {
        color: 'rgba(255,255,255,0.9)',
        fontSize: 15,
        lineHeight: 24,
        marginBottom: 16,
    },
    postImage: {
        width: '100%',
        height: 280,
        borderRadius: 16,
        marginBottom: 16,
    },
    actionBar: {
        flexDirection: 'row',
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
        paddingTop: 16,
        gap: 28,
    },
    actionButton: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    actionText: {
        color: Theme.colors.textSecondary,
        fontSize: 13,
        fontWeight: '600',
    },

    // Comments
    commentSection: {
        marginTop: 20,
        paddingTop: 16,
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
    },
    commentRow: {
        flexDirection: 'row',
        marginBottom: 16,
    },
    commentAvatar: {
        width: 32, 
        height: 32, 
        borderRadius: 16,
        marginRight: 12,
    },
    commentBubble: {
        flex: 1,
        backgroundColor: 'rgba(255,255,255,0.03)',
        padding: 12,
        borderRadius: 16,
        borderTopLeftRadius: 4,
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.03)',
    },
    commentUser: {
        color: Theme.colors.textPrimary,
        fontSize: 13,
        fontWeight: '700',
        marginBottom: 2,
    },
    commentText: {
        color: Theme.colors.textSecondary,
        fontSize: 14,
        lineHeight: 20,
    },
    addCommentRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: 12,
        backgroundColor: '#000',
        borderRadius: 24,
        paddingHorizontal: 12,
        paddingVertical: 6,
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.05)',
    },
    commentAvatarSmall: {
        width: 24,
        height: 24,
        borderRadius: 12,
        marginRight: 8,
    },
    commentInput: {
        flex: 1,
        height: 36,
        color: Theme.colors.textPrimary,
        fontSize: 14,
        marginRight: 8,
    },

    // Modal
    modalContainer: {
        flex: 1,
        justifyContent: 'flex-end',
    },
    modalContent: {
        height: '92%',
        borderTopLeftRadius: 32,
        borderTopRightRadius: 32,
        overflow: 'hidden',
        padding: 24,
    },
    modalHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 24,
    },
    modalTitle: {
        color: Theme.colors.textPrimary,
        fontSize: 20,
        fontWeight: '800',
        letterSpacing: -0.5,
    },
    postButton: {
        backgroundColor: Theme.colors.primary,
        paddingHorizontal: 20,
        paddingVertical: 8,
        borderRadius: 20,
    },
    postButtonText: {
        color: '#000',
        fontWeight: '800',
        fontSize: 14,
        textTransform: 'uppercase',
        letterSpacing: 0.5,
    },
    postInput: {
        flex: 1,
        color: Theme.colors.textPrimary,
        fontSize: 18,
        textAlignVertical: 'top',
        lineHeight: 28,
    },
    attachmentBar: {
        flexDirection: 'row',
        paddingTop: 20,
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
    },
    attachButton: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 10,
        paddingHorizontal: 16,
        borderRadius: 12,
        backgroundColor: 'rgba(255,255,255,0.05)',
        gap: 10,
    },
    attachText: {
        color: Theme.colors.textPrimary,
        fontWeight: '700',
        fontSize: 14,
    },
});
