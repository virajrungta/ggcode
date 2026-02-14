import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createStackNavigator } from '@react-navigation/stack';
import { Theme } from '../theme';
import { Home, Users, BarChart3, Leaf } from 'lucide-react-native';
import { Platform, View } from 'react-native';

// Screens
import DashboardScreen from '../screens/DashboardScreen';
import CommunityScreen from '../screens/CommunityScreen';
import AnalyticsScreen from '../screens/AnalyticsScreen';
import LoginScreen from '../screens/LoginScreen';
import PlantGroupScreen from '../screens/Community/PlantGroupScreen';
import CreateCommunityScreen from '../screens/Community/CreateCommunityScreen';

const Tab = createBottomTabNavigator();
const Stack = createStackNavigator();

function TabNavigator() {
  return (
    <Tab.Navigator
      id="BottomTabNavigator"
      screenOptions={{
        headerShown: false,
        tabBarShowLabel: false, // Don't label them
        tabBarStyle: {
          backgroundColor: '#050A07',
          borderTopWidth: 1,
          borderTopColor: '#1A1A1A',
          height: Platform.OS === 'ios' ? 88 : 70,
          elevation: 0,
          position: 'absolute', // Make it feel more integrated
          bottom: 0,
          left: 0,
          right: 0,
        },
        tabBarActiveTintColor: Theme.colors.primary,
        tabBarInactiveTintColor: '#444',
      }}
    >
      <Tab.Screen 
        name="Dashboard" 
        component={DashboardScreen} 
        options={{
          tabBarIcon: ({ color }) => (
            <View style={styles.tabIconContainer}>
              <Home size={26} color={color} strokeWidth={2} />
            </View>
          ),
        }}
      />
      <Tab.Screen 
        name="Community" 
        component={CommunityScreen} 
        options={{
          tabBarIcon: ({ color }) => (
            <View style={styles.tabIconContainer}>
              <Users size={26} color={color} strokeWidth={2} />
            </View>
          ),
        }}
      />
      <Tab.Screen 
        name="Analytics" 
        component={AnalyticsScreen} 
        options={{
          tabBarIcon: ({ color }) => (
            <View style={styles.tabIconContainer}>
              <BarChart3 size={26} color={color} strokeWidth={2} />
            </View>
          ),
        }}
      />
    </Tab.Navigator>
  );
}

const styles = {
  tabIconContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    width: 60,
  }
} as any;

export default function AppNavigator() {
  return (
    <Stack.Navigator
        id="MainStackNavigator"
        screenOptions={{
            headerShown: false,
            cardStyle: { backgroundColor: '#fff' }
        }}
    >
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen name="Main" component={TabNavigator} />
      <Stack.Screen name="PlantGroup" component={PlantGroupScreen} />
      <Stack.Screen name="CreateCommunity" component={CreateCommunityScreen} />
    </Stack.Navigator>
  );
}
