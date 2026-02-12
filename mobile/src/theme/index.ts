const PALETTE = {
  // Deep Jungle / Cyber Organic
  neonGreen: '#D4FF00', // The "Volt" accent
  darkBlack: '#050A07', // Main Background
  cardDark: '#0F1612',  // Card Background
  textGray: '#A0A0A0',
  
  // Accents for rings/charts
  neonBlue: '#2DE2E6',
  neonPink: '#F706CF',
  neonOrange: '#FF9100',
  
  white: '#FFFFFF',
  black: '#000000',

  // Status
  good: '#D4FF00',
  warning: '#FF9100',
  bad: '#F706CF',
};

export const Theme = {
  colors: {
    primary: PALETTE.neonGreen,
    primarySubtle: 'rgba(212, 255, 0, 0.15)', // Low opacity volt
    secondary: PALETTE.neonBlue,
    
    bgMain: PALETTE.darkBlack,
    surface: PALETTE.cardDark,
    
    textPrimary: PALETTE.white,
    textSecondary: PALETTE.textGray,
    textTertiary: '#555555',
    
    statusGood: PALETTE.good,
    statusWarning: PALETTE.warning,
    statusBad: PALETTE.bad,
    textInverse: PALETTE.white,
  },

  spacing: {
    xs: 4,
    s: 8,
    m: 16,
    l: 24,
    xl: 32,
    xxl: 48,
  },

  radius: {
    xs: 4,
    s: 8,
    m: 12,
    l: 16,
    xl: 24,
    round: 9999,
  },

  typography: {
    // Display - for large headers
    displayLarge: {
      fontSize: 32,
      fontWeight: "600" as const,
      letterSpacing: -0.5,
      lineHeight: 40,
    },
    displayMedium: {
      fontSize: 28,
      fontWeight: "600" as const,
      letterSpacing: -0.3,
      lineHeight: 36,
    },

    // Headlines
    headlineLarge: {
      fontSize: 24,
      fontWeight: "600" as const,
      letterSpacing: 0,
      lineHeight: 32,
    },
    headlineMedium: {
      fontSize: 20,
      fontWeight: "600" as const,
      letterSpacing: 0,
      lineHeight: 28,
    },
    headlineSmall: {
      fontSize: 18,
      fontWeight: "600" as const,
      letterSpacing: 0,
      lineHeight: 24,
    },

    // Body text
    bodyLarge: {
      fontSize: 16,
      fontWeight: "400" as const,
      letterSpacing: 0.15,
      lineHeight: 24,
    },
    bodyMedium: {
      fontSize: 14,
      fontWeight: "400" as const,
      letterSpacing: 0.25,
      lineHeight: 20,
    },
    bodySmall: {
      fontSize: 12,
      fontWeight: "400" as const,
      letterSpacing: 0.4,
      lineHeight: 16,
    },

    // Labels
    labelLarge: {
      fontSize: 14,
      fontWeight: "500" as const,
      letterSpacing: 0.1,
      lineHeight: 20,
    },
    labelMedium: {
      fontSize: 12,
      fontWeight: "500" as const,
      letterSpacing: 0.5,
      lineHeight: 16,
    },
    labelSmall: {
      fontSize: 11,
      fontWeight: "500" as const,
      letterSpacing: 0.5,
      lineHeight: 16,
    },
  },
};

import { StyleSheet } from "react-native";

// Standard card styles - Updated for Dark Mode
export const CardStyles = StyleSheet.create({
  container: {
    backgroundColor: Theme.colors.surface,
    borderRadius: Theme.radius.l,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  containerElevated: {
    backgroundColor: Theme.colors.surface,
    borderRadius: Theme.radius.l,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.5,
    shadowRadius: 16,
    elevation: 8,
  },
});

// Deprecated - kept for compatibility but darkened
export const GlassStyles = StyleSheet.create({
  panel: {
    backgroundColor: Theme.colors.surface,
    borderRadius: Theme.radius.l,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
  card: {
    backgroundColor: Theme.colors.surface,
    borderRadius: Theme.radius.l,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
});
