import { 
  collection, 
  doc, 
  setDoc, 
  getDoc, 
  getDocs, 
  updateDoc, 
  deleteDoc, 
  onSnapshot,
  query, 
  orderBy,
  Timestamp,
  addDoc,
} from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, storage } from './config';
import { getCurrentUser } from './authService';
import { Pot, PlantData, SensorData } from '../utils/types';

// ===========================
// POTS (Firestore)
// ===========================

function getUserPotsRef() {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  return collection(db, 'users', user.uid, 'pots');
}

// Save a new pot
export async function savePot(pot: Pot): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  await setDoc(doc(db, 'users', user.uid, 'pots', pot.id), {
    name: pot.name,
    plantData: pot.plantData ? {
      id: pot.plantData.id,
      name: pot.plantData.name,
      scientificName: pot.plantData.scientificName,
      imageUrl: pot.plantData.imageUrl || null,
      compatible: pot.plantData.compatible,
      confidence: pot.plantData.confidence || null,
    } : null,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
}

// Get all pots for the current user
export async function getPots(): Promise<Pot[]> {
  const user = getCurrentUser();
  if (!user) return [];
  
  const potsRef = collection(db, 'users', user.uid, 'pots');
  const q = query(potsRef, orderBy('createdAt', 'desc'));
  const snapshot = await getDocs(q);
  
  return snapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      plantData: data.plantData || null,
    } as Pot;
  });
}

// Update plant data for a pot
export async function updatePotPlant(potId: string, plantData: PlantData): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  await updateDoc(doc(db, 'users', user.uid, 'pots', potId), {
    plantData: {
      id: plantData.id,
      name: plantData.name,
      scientificName: plantData.scientificName,
      imageUrl: plantData.imageUrl || null,
      compatible: plantData.compatible,
      confidence: plantData.confidence || null,
    },
    updatedAt: Timestamp.now(),
  });
}

// Delete a pot
export async function deletePot(potId: string): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  await deleteDoc(doc(db, 'users', user.uid, 'pots', potId));
}

// Real-time listener for pots
export function subscribeToPots(callback: (pots: Pot[]) => void) {
  const user = getCurrentUser();
  if (!user) return () => {};
  
  const potsRef = collection(db, 'users', user.uid, 'pots');
  const q = query(potsRef, orderBy('createdAt', 'desc'));
  
  return onSnapshot(q, (snapshot) => {
    const pots = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        name: data.name,
        plantData: data.plantData || null,
      } as Pot;
    });
    callback(pots);
  });
}

// ===========================
// SENSOR DATA HISTORY (Firestore)
// ===========================

export async function saveSensorReading(potId: string, sensorData: SensorData): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  await addDoc(collection(db, 'users', user.uid, 'pots', potId, 'sensorHistory'), {
    ...sensorData,
    timestamp: Timestamp.now(),
  });
}

export async function getSensorHistory(potId: string, limit: number = 50): Promise<(SensorData & { timestamp: Date })[]> {
  const user = getCurrentUser();
  if (!user) return [];
  
  const historyRef = collection(db, 'users', user.uid, 'pots', potId, 'sensorHistory');
  const q = query(historyRef, orderBy('timestamp', 'desc'));
  const snapshot = await getDocs(q);
  
  return snapshot.docs.slice(0, limit).map(doc => {
    const data = doc.data();
    return {
      temperature: data.temperature,
      humidity: data.humidity,
      light: data.light,
      soilMoisture: data.soilMoisture,
      timestamp: data.timestamp.toDate(),
    };
  });
}

// ===========================
// GROWTH TRACKING (Firestore)
// ===========================

export interface GrowthEntry {
  height: number;
  leaves: number;
  healthScore: number;
  notes?: string;
  timestamp: Date;
}

export async function saveGrowthEntry(potId: string, entry: Omit<GrowthEntry, 'timestamp'>): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  await addDoc(collection(db, 'users', user.uid, 'pots', potId, 'growthHistory'), {
    ...entry,
    timestamp: Timestamp.now(),
  });
}

export async function getGrowthHistory(potId: string): Promise<GrowthEntry[]> {
  const user = getCurrentUser();
  if (!user) return [];
  
  const historyRef = collection(db, 'users', user.uid, 'pots', potId, 'growthHistory');
  const q = query(historyRef, orderBy('timestamp', 'asc'));
  const snapshot = await getDocs(q);
  
  return snapshot.docs.map(doc => {
    const data = doc.data();
    return {
      height: data.height,
      leaves: data.leaves,
      healthScore: data.healthScore,
      notes: data.notes || '',
      timestamp: data.timestamp.toDate(),
    };
  });
}

// Subscribe to growth data in real-time
export function subscribeToGrowthHistory(potId: string, callback: (entries: GrowthEntry[]) => void) {
  const user = getCurrentUser();
  if (!user) return () => {};
  
  const historyRef = collection(db, 'users', user.uid, 'pots', potId, 'growthHistory');
  const q = query(historyRef, orderBy('timestamp', 'asc'));
  
  return onSnapshot(q, (snapshot) => {
    const entries = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        height: data.height,
        leaves: data.leaves,
        healthScore: data.healthScore,
        notes: data.notes || '',
        timestamp: data.timestamp.toDate(),
      };
    });
    callback(entries);
  });
}

// ===========================
// COMMUNITIES (Firestore)
// ===========================

export interface Community {
  id: string;
  name: string;
  members: number;
  imageUrl: string;
  description?: string;
  createdBy: string;
}

export async function getCommunities(): Promise<Community[]> {
  const snapshot = await getDocs(collection(db, 'communities'));
  
  return snapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      members: data.members || 0,
      imageUrl: data.imageUrl || '',
      description: data.description || '',
      createdBy: data.createdBy || '',
    };
  });
}

export function subscribeToCommunities(callback: (communities: Community[]) => void) {
  return onSnapshot(collection(db, 'communities'), (snapshot) => {
    const communities = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        name: data.name,
        members: data.members || 0,
        imageUrl: data.imageUrl || '',
        description: data.description || '',
        createdBy: data.createdBy || '',
      };
    });
    callback(communities);
  });
}

export async function createCommunity(community: Omit<Community, 'id'>): Promise<string> {
  const docRef = await addDoc(collection(db, 'communities'), {
    ...community,
    createdAt: Timestamp.now(),
  });
  return docRef.id;
}

export async function joinCommunity(communityId: string): Promise<void> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  // Add user to community members
  await setDoc(doc(db, 'communities', communityId, 'members', user.uid), {
    userId: user.uid,
    joinedAt: Timestamp.now(),
  });
  
  // TODO: Increment member count via Cloud Function or transaction
}

// ===========================
// IMAGE UPLOAD (Firebase Storage)
// ===========================

export async function uploadPlantImage(base64: string, potId: string): Promise<string> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  // Convert base64 to blob
  const response = await fetch(`data:image/jpeg;base64,${base64}`);
  const blob = await response.blob();
  
  const imageRef = ref(storage, `users/${user.uid}/plants/${potId}_${Date.now()}.jpg`);
  await uploadBytes(imageRef, blob);
  
  return await getDownloadURL(imageRef);
}

export async function uploadCommunityImage(base64: string, communityName: string): Promise<string> {
  const user = getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  const response = await fetch(`data:image/jpeg;base64,${base64}`);
  const blob = await response.blob();
  
  const imageRef = ref(storage, `communities/${communityName}_${Date.now()}.jpg`);
  await uploadBytes(imageRef, blob);
  
  return await getDownloadURL(imageRef);
}

// ===========================
// SEED INITIAL DATA (For first-time setup)
// ===========================

export async function seedCommunitiesIfEmpty(): Promise<void> {
  const snapshot = await getDocs(collection(db, 'communities'));
  
  if (snapshot.empty) {
    const defaultCommunities = [
      { name: 'SUCCULENT LOVERS', members: 12500, imageUrl: 'https://images.unsplash.com/photo-1459416493396-b6b9372901c0?q=80&w=400&auto=format&fit=crop', description: 'A community for succulent enthusiasts', createdBy: 'system' },
      { name: 'INDOOR JUNGLE', members: 8200, imageUrl: 'https://images.unsplash.com/photo-1463320726281-696a485928c7?q=80&w=400&auto=format&fit=crop', description: 'Transform your space into a green paradise', createdBy: 'system' },
      { name: 'ORCHID WHISPERERS', members: 3100, imageUrl: 'https://images.unsplash.com/photo-1566933294862-4090d279361a?q=80&w=400&auto=format&fit=crop', description: 'Master the art of orchid care', createdBy: 'system' },
      { name: 'VEG GARDENERS', members: 45000, imageUrl: 'https://images.unsplash.com/photo-1592419044706-39796d40f98c?q=80&w=400&auto=format&fit=crop', description: 'Grow your own food at home', createdBy: 'system' },
    ];
    
    for (const community of defaultCommunities) {
      await addDoc(collection(db, 'communities'), {
        ...community,
        createdAt: Timestamp.now(),
      });
    }
  }
}
