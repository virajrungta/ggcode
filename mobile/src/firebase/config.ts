import { initializeApp } from "firebase/app";
import { initializeAuth, browserLocalPersistence } from "firebase/auth";
// @ts-ignore - getReactNativePersistence exists at runtime but is not in the TS types
import { getReactNativePersistence } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getStorage } from "firebase/storage";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";

// Your web app's Firebase configuration
const firebaseConfig = {
  apiKey: "AIzaSyByYuqWpw8mLWW2QPEgVO390DjZ4DoRfWM",
  authDomain: "greengenius-b9d6f.firebaseapp.com",
  projectId: "greengenius-b9d6f",
  storageBucket: "greengenius-b9d6f.firebasestorage.app",
  messagingSenderId: "692586410505",
  appId: "1:692586410505:web:93b7c4f656fdd743abbed8",
  measurementId: "G-P85089EV6W",
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Firebase Auth with Persistence
let auth;
if (Platform.OS === "web") {
  auth = initializeAuth(app, {
    persistence: browserLocalPersistence,
  });
} else {
  auth = initializeAuth(app, {
    persistence: getReactNativePersistence(AsyncStorage),
  });
}

// Initialize Firestore
const db = getFirestore(app);

// Initialize Storage
const storage = getStorage(app);

export { app, auth, db, storage };
