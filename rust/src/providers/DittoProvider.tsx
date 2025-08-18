import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface DittoContextType {
  isInitialized: boolean;
  isInitializing: boolean;
  error: string | null;
  initializeDitto: () => Promise<void>;
  getDittoStatus: () => Promise<string>;
}

const DittoContext = createContext<DittoContextType | undefined>(undefined);

interface DittoProviderProps {
  children: ReactNode;
}

export const DittoProvider: React.FC<DittoProviderProps> = ({ children }) => {
  const [isInitialized, setIsInitialized] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const initializeDitto = async () => {
    if (isInitialized || isInitializing) {
      return; // Prevent multiple initialization attempts
    }

    setIsInitializing(true);
    setError(null);

    try {
      const result = await invoke<string>("initialize_ditto");
      console.log("Ditto initialized:", result);
      setIsInitialized(true);
    } catch (error) {
      const errorMessage = `Failed to initialize Ditto: ${error}`;
      console.error(errorMessage);
      setError(errorMessage);
    } finally {
      setIsInitializing(false);
    }
  };

  const getDittoStatus = async (): Promise<string> => {
    try {
      return await invoke<string>("get_ditto_status");
    } catch (error) {
      throw new Error(`Failed to get Ditto status: ${error}`);
    }
  };

  const checkInitializationStatus = async () => {
    try {
      const initialized = await invoke<boolean>("is_ditto_initialized");
      setIsInitialized(initialized);
    } catch (error) {
      console.error("Failed to check Ditto initialization status:", error);
    }
  };

  // Check initialization status on mount
  useEffect(() => {
    checkInitializationStatus();
  }, []);

  // Auto-initialize Ditto on app launch (only for main window, not logs window)
  useEffect(() => {
    // Skip auto-initialization for logs window
    if ((window as any).__IS_LOGS_WINDOW__) {
      return;
    }

    // Only auto-initialize if not already initialized and not currently initializing
    if (!isInitialized && !isInitializing) {
      initializeDitto();
    }
  }, [isInitialized, isInitializing]);

  const value: DittoContextType = {
    isInitialized,
    isInitializing,
    error,
    initializeDitto,
    getDittoStatus,
  };

  return (
    <DittoContext.Provider value={value}>
      {children}
    </DittoContext.Provider>
  );
};

export const useDitto = (): DittoContextType => {
  const context = useContext(DittoContext);
  if (context === undefined) {
    throw new Error('useDitto must be used within a DittoProvider');
  }
  return context;
};