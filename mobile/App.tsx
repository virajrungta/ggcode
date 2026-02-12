import React, { useState, useEffect, useCallback } from 'react';
import { StyleSheet, StatusBar } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { NavigationContainer } from '@react-navigation/native';
import * as Font from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import { 
  Outfit_400Regular, 
  Outfit_600SemiBold, 
  Outfit_700Bold, 
  Outfit_800ExtraBold 
} from '@expo-google-fonts/outfit';
import { 
  Inter_400Regular, 
  Inter_500Medium, 
  Inter_600SemiBold 
} from '@expo-google-fonts/inter';

import { Theme } from './src/theme';
import AppNavigator from './src/navigation/AppNavigator';

// Keep splash screen visible while loading resources
SplashScreen.preventAutoHideAsync();

export default function App() {
  const [appIsReady, setAppIsReady] = useState(false);

  useEffect(() => {
    async function prepare() {
      try {
        await Font.loadAsync({
          'Outfit_Regular': Outfit_400Regular,
          'Outfit_SemiBold': Outfit_600SemiBold,
          'Outfit_Bold': Outfit_700Bold,
          'Outfit_ExtraBold': Outfit_800ExtraBold,
          'Inter_Regular': Inter_400Regular,
          'Inter_Medium': Inter_500Medium,
          'Inter_SemiBold': Inter_600SemiBold,
        });
      } catch (e) {
        console.warn(e);
      } finally {
        setAppIsReady(true);
      }
    }

    prepare();
  }, []);

  const onLayoutRootView = useCallback(async () => {
    if (appIsReady) {
      await SplashScreen.hideAsync();
    }
  }, [appIsReady]);

  if (!appIsReady) {
    return null;
  }

  return (
    <SafeAreaProvider onLayout={onLayoutRootView}>
      <StatusBar barStyle="dark-content" backgroundColor="transparent" translucent />
      <NavigationContainer>
        <AppNavigator />
      </NavigationContainer>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Theme.colors.bgMain,
  },
});
