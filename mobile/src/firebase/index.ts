export { app, auth, db, storage } from './config';
export { signIn, signUp, signOut, onAuthChanged, getCurrentUser } from './authService';
export { 
  savePot, 
  getPots, 
  updatePotPlant, 
  deletePot, 
  subscribeToPots,
  saveSensorReading,
  getSensorHistory,
  saveGrowthEntry,
  getGrowthHistory,
  subscribeToGrowthHistory,
  getCommunities,
  subscribeToCommunities,
  createCommunity,
  joinCommunity,
  uploadPlantImage,
  uploadCommunityImage,
  wipeAllCommunities,
} from './firestoreService';
export type { GrowthEntry, Community } from './firestoreService';
