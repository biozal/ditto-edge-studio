import React, { useState, useEffect } from 'react';
import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';
import { Plus, RefreshCw } from 'lucide-react';
import { DittoAppConfig } from '../models/DittoAppConfig';
import { useAppConfig } from '../hooks/useAppConfig';
import { useDitto } from '../providers/DittoProvider';
import AppCard from './AppCard';
import AddAppConfigModal from './AddAppConfigModal';
import ErrorModal from './ErrorModal';
import { Button } from './ui/button';

const AppListing: React.FC = () => {
  const [appConfigs, setAppConfigs] = useState<DittoAppConfig[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [editingConfig, setEditingConfig] = useState<DittoAppConfig | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [, setObserverRegistered] = useState(false);
  
  const { deleteAppConfig } = useAppConfig();
  const { isInitialized, isInitializing, error: dittoError } = useDitto();

  // Set up event listener first, then register observer when Ditto is initialized
  useEffect(() => {
    if (!isInitialized) return;

    console.log('Setting up event listener and registering observer...');
    
    // Set up the event listener first
    const unlisten = listen<DittoAppConfig[]>('app-configs-updated', async (event) => {
      console.log('Received app configs update from observer:', event.payload);
      
      // Use the data directly from the observer event
      setAppConfigs(event.payload);
      setIsLoading(false);
      
      console.log('Set isLoading to false, app configs length:', event.payload.length);
    });

    // Then register the observer
    const registerObserver = async () => {
      try {
        console.log('Ditto is initialized, registering observer...');
        await invoke('register_app_config_observer');
        setObserverRegistered(true);
        console.log('App config observer registered successfully');
        // The observer will emit the initial data automatically
      } catch (error) {
        console.error('Failed to register observer:', error);
        setError(`Failed to register real-time updates: ${error}`);
        setIsLoading(false); // Stop loading on error
      }
    };

    registerObserver();

    return () => {
      unlisten.then(fn => fn());
    };
  }, [isInitialized]);

  // No need for initial manual fetch - the observer will provide initial data when registered

  const handleAddApp = () => {
    setEditingConfig(null);
    setShowAddModal(true);
  };

  const handleEditApp = (config: DittoAppConfig) => {
    setEditingConfig(config);
    setShowAddModal(true);
  };

  const handleDeleteApp = async (configId: string) => {
    const confirmed = window.confirm('Are you sure you want to delete this app configuration?');
    if (!confirmed) return;

    const success = await deleteAppConfig(configId);
    if (!success) {
      setError('Failed to delete app configuration');
    }
    // Observer will automatically update the list
  };

  const handleModalClose = () => {
    setShowAddModal(false);
    setEditingConfig(null);
  };

  const handleModalSuccess = () => {
    setShowAddModal(false);
    setEditingConfig(null);
    // Observer will automatically update the list
  };


  // Show initialization spinner while Ditto is starting up
  if (isInitializing || (!isInitialized && !dittoError)) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-4 text-slate-400" />
          <p className="text-slate-400">Initializing Ditto...</p>
          <p className="text-xs text-slate-500 mt-2">Please wait while we set up the database connection</p>
        </div>
      </div>
    );
  }

  // Show error if Ditto failed to initialize
  if (dittoError) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <RefreshCw className="w-8 h-8 text-red-600" />
          </div>
          <h3 className="text-lg font-medium text-slate-100 mb-2">Initialization Failed</h3>
          <p className="text-slate-400 mb-4">{dittoError}</p>
          <Button
            onClick={() => window.location.reload()}
            className="bg-red-600 hover:bg-red-700 text-white"
          >
            Retry
          </Button>
        </div>
      </div>
    );
  }

  // Show loading spinner while fetching app data
  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-4 text-slate-400" />
          <p className="text-slate-400">Loading apps...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-slate-100">Ditto Apps</h2>
          <p className="text-slate-400 mt-1">
            {appConfigs.length} {appConfigs.length === 1 ? 'app' : 'apps'} configured
          </p>
        </div>
        <Button
          onClick={handleAddApp}
          className="bg-blue-600 hover:bg-blue-700 text-white"
          disabled={!isInitialized}
        >
          <Plus className="w-4 h-4 mr-2" />
          Add App
        </Button>
      </div>

      {/* App Grid */}
      {appConfigs.length === 0 ? (
        <div className="text-center py-12">
          <div className="w-16 h-16 bg-slate-700 rounded-full flex items-center justify-center mx-auto mb-4">
            <Plus className="w-8 h-8 text-slate-400" />
          </div>
          <h3 className="text-lg font-medium text-slate-100 mb-2">No apps configured</h3>
          <p className="text-slate-400 mb-6">
            Get started by adding your first Ditto app configuration
          </p>
          <Button
            onClick={handleAddApp}
            className="bg-blue-600 hover:bg-blue-700 text-white"
            disabled={!isInitialized}
          >
            <Plus className="w-4 h-4 mr-2" />
            Add Your First App
          </Button>
        </div>
      ) : (
        <div className="grid gap-6 md:grid-cols-1 lg:grid-cols-2">
          {appConfigs.map((config) => (
            <AppCard
              key={config._id}
              config={config}
              onEdit={handleEditApp}
              onDelete={handleDeleteApp}
            />
          ))}
        </div>
      )}

      {/* Modals */}
      {showAddModal && (
        <AddAppConfigModal
          isOpen={showAddModal}
          onClose={handleModalClose}
          onError={setError}
          onSuccess={handleModalSuccess}
          editingConfig={editingConfig}
        />
      )}

      {error && (
        <ErrorModal
          error={error}
          onClose={() => setError(null)}
        />
      )}
    </div>
  );
};

export default AppListing;