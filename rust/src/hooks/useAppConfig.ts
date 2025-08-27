import { useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { DittoAppConfig } from '../models/DittoAppConfig';
import { useDitto } from '../providers/DittoProvider';

interface UseAppConfigReturn {
  isLoading: boolean;
  error: string | null;
  saveAppConfig: (config: DittoAppConfig) => Promise<boolean>;
  addAppConfig: (config: DittoAppConfig) => Promise<boolean>;
  updateAppConfig: (config: DittoAppConfig) => Promise<boolean>;
  deleteAppConfig: (configId: string) => Promise<boolean>;
  getAllAppConfigs: () => Promise<DittoAppConfig[] | null>;
  clearError: () => void;
}

/**
 * Hook for managing Ditto app configurations
 * Handles all backend communication for CRUD operations
 */
export const useAppConfig = (): UseAppConfigReturn => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { isInitialized, isInitializing, initializeDitto } = useDitto();

  const clearError = () => setError(null);

  const ensureDittoInitialized = async (): Promise<boolean> => {
    if (isInitialized) {
      return true;
    }
    
    if (isInitializing) {
      // Wait for current initialization to complete
      return new Promise((resolve) => {
        const checkInterval = setInterval(() => {
          if (isInitialized || (!isInitializing && !isInitialized)) {
            clearInterval(checkInterval);
            resolve(isInitialized);
          }
        }, 100);
      });
    }
    
    // Try to initialize if not already initialized
    try {
      await initializeDitto();
      return isInitialized;
    } catch (error) {
      setError(`Failed to initialize Ditto: ${error}`);
      return false;
    }
  };

  const saveAppConfig = async (config: DittoAppConfig): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    
    try {
      // Ensure Ditto is initialized before proceeding
      const initialized = await ensureDittoInitialized();
      if (!initialized) {
        return false;
      }
      
      await invoke('save_ditto_app_config', { config });
      return true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to save app config: ${errorMessage}`);
      return false;
    } finally {
      setIsLoading(false);
    }
  };

  const addAppConfig = async (config: DittoAppConfig): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    
    try {
      // Ensure Ditto is initialized before proceeding
      const initialized = await ensureDittoInitialized();
      if (!initialized) {
        return false;
      }
      
      await invoke('add_ditto_app_config', { config });
      return true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to save app config: ${errorMessage}`);
      return false;
    } finally {
      setIsLoading(false);
    }
  };

  const updateAppConfig = async (config: DittoAppConfig): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    
    try {
      const initialized = await ensureDittoInitialized();
      if (!initialized) {
        return false;
      }
      
      await invoke('update_ditto_app_config', { config });
      return true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to update app config: ${errorMessage}`);
      return false;
    } finally {
      setIsLoading(false);
    }
  };

  const deleteAppConfig = async (configId: string): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    
    try {
      const initialized = await ensureDittoInitialized();
      if (!initialized) {
        return false;
      }
      
      await invoke('delete_ditto_app_config', { configId });
      return true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to delete app config: ${errorMessage}`);
      return false;
    } finally {
      setIsLoading(false);
    }
  };

  const getAllAppConfigs = async (): Promise<DittoAppConfig[] | null> => {
    setIsLoading(true);
    setError(null);
    
    try {
      const initialized = await ensureDittoInitialized();
      if (!initialized) {
        return null;
      }
      
      const configs = await invoke<DittoAppConfig[]>('get_all_ditto_app_configs');
      return configs;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to fetch app configs: ${errorMessage}`);
      return null;
    } finally {
      setIsLoading(false);
    }
  };

  return {
    isLoading,
    error,
    saveAppConfig,
    addAppConfig,
    updateAppConfig,
    deleteAppConfig,
    getAllAppConfigs,
    clearError,
  };
};