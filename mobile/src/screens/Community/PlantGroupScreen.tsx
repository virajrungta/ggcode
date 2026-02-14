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
        height: 280,
        width: '100%',
        position: 'relative',
    },
    coverImage: {
        width: '100%',
        height: '100%',
    },
    coverOverlay: {
        ...StyleSheet.absoluteFillObject,
        backgroundColor: 'rgba(0,0,0,0.3)',
        // gradient effect could be nice here
    },
    navBar: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        paddingHorizontal: 16,
        paddingTop: 10,
    },
    iconButtonBlur: {
        width: 40, 
        height: 40,
        borderRadius: 20,
        overflow: 'hidden',
        alignItems: 'center',
        justifyContent: 'center',
    },
    groupInfoContainer: {
        position: 'absolute',
        bottom: 20,
        left: 20,
        right: 20,
    },
    tagsRow: {
        flexDirection: 'row',
        gap: 8,
        marginBottom: 8,
    },
    tagBadge: {
        backgroundColor: Theme.colors.primary,
        paddingHorizontal: 8,
        paddingVertical: 4,
        borderRadius: 4,
    },
    tagText: {
        color: '#000',
        fontSize: 10,
        fontWeight: '700',
    },
    groupName: {
        fontSize: 32,
        fontWeight: '800',
        color: '#fff',
        textShadowColor: 'rgba(0,0,0,0.5)',
        textShadowOffset: { width: 0, height: 2 },
        textShadowRadius: 4,
        marginBottom: 4,
    },
    groupMembers: {
        color: '#ddd',
        fontSize: 14,
        fontWeight: '500',
    },
    descriptionContainer: {
        padding: 20,
        backgroundColor: '#0F1612',
        borderBottomWidth: 1,
        borderBottomColor: '#222',
    },
    descriptionText: {
        color: '#ccc',
        fontSize: 14,
        lineHeight: 22,
    },
    createPostTrigger: {
        backgroundColor: '#1A241E',
        marginHorizontal: 16,
        marginTop: 16,
        padding: 12,
        borderRadius: 12,
        flexDirection: 'row',
        alignItems: 'center',
        borderWidth: 1,
        borderColor: '#333',
    },
    triggerAvatar: {
        width: 36, 
        height: 36,
        borderRadius: 18,
        marginRight: 12,
    },
    triggerText: {
        flex: 1,
        color: '#666',
        fontSize: 14,
    },
    feedTabs: {
        flexDirection: 'row',
        marginHorizontal: 16,
        marginTop: 20,
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        gap: 24,
    },
    tabText: {
        fontSize: 16,
        color: '#666',
        paddingBottom: 12,
        fontWeight: '600',
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
        backgroundColor: 'rgba(20,20,20,0.6)', // Glassy override
    },
    postHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 12,
    },
    userAvatar: {
        width: 40,
        height: 40,
        borderRadius: 20,
        marginRight: 10,
    },
    userName: {
        color: '#fff',
        fontWeight: '700',
        fontSize: 15,
    },
    roleBadge: {
        backgroundColor: '#333',
        paddingHorizontal: 6,
        paddingVertical: 2,
        borderRadius: 4,
    },
    roleText: {
        fontSize: 10,
        color: '#ccc',
        fontWeight: '600',
    },
    timestamp: {
        color: '#666',
        fontSize: 12,
        marginTop: 1,
    },
    postContent: {
        color: '#eee',
        fontSize: 15,
        lineHeight: 22,
        marginBottom: 12,
    },
    postImage: {
        width: '100%',
        height: 250,
        borderRadius: 12,
        marginBottom: 12,
    },
    actionBar: {
        flexDirection: 'row',
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
        paddingTop: 12,
        gap: 24,
    },
    actionButton: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
    },
    actionText: {
        color: '#888',
        fontSize: 14,
        fontWeight: '500',
    },

    // Comments
    commentSection: {
        marginTop: 16,
        paddingTop: 16,
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
    },
    commentRow: {
        flexDirection: 'row',
        marginBottom: 12,
    },
    commentAvatar: {
        width: 28, 
        height: 28, 
        borderRadius: 14,
        marginRight: 10,
    },
    commentBubble: {
        flex: 1,
        backgroundColor: 'rgba(255,255,255,0.05)',
        padding: 10,
        borderRadius: 12,
        borderTopLeftRadius: 2,
    },
    commentUser: {
        color: '#ddd',
        fontSize: 12,
        fontWeight: '700',
        marginBottom: 2,
    },
    commentText: {
        color: '#bbb',
        fontSize: 13,
    },
    addCommentRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: 8,
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
        backgroundColor: 'rgba(0,0,0,0.2)',
        borderRadius: 18,
        paddingHorizontal: 12,
        color: '#fff',
        marginRight: 8,
        fontSize: 13,
    },

    // Modal
    modalContainer: {
        flex: 1,
        justifyContent: 'flex-end',
    },
    modalContent: {
        height: '90%',
        borderTopLeftRadius: 24,
        borderTopRightRadius: 24,
        overflow: 'hidden',
        padding: 20,
    },
    modalHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 20,
    },
    modalTitle: {
        color: '#fff',
        fontSize: 18,
        fontWeight: '700',
    },
    postButton: {
        backgroundColor: Theme.colors.primary,
        paddingHorizontal: 16,
        paddingVertical: 6,
        borderRadius: 20,
    },
    postButtonText: {
        color: '#000',
        fontWeight: '700',
        fontSize: 14,
    },
    postInput: {
        flex: 1,
        color: '#fff',
        fontSize: 18,
        textAlignVertical: 'top',
    },
    attachmentBar: {
        flexDirection: 'row',
        paddingTop: 16,
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.1)',
    },
    attachButton: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 8,
        borderRadius: 8,
        backgroundColor: 'rgba(255,255,255,0.1)',
        gap: 8,
    },
    attachText: {
        color: '#fff',
        fontWeight: '500',
    },
});
