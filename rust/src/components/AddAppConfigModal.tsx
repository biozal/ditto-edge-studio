import React, { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import { DittoAppConfig, createNewDittoAppConfig } from '../models/DittoAppConfig';
import { useAppConfig } from '../hooks/useAppConfig';

interface AddAppConfigModalProps {
  isOpen: boolean;
  onClose: () => void;
  onError: (error: string) => void;
  onSuccess?: () => void;
  editingConfig?: DittoAppConfig | null;
}

const AddAppConfigModal: React.FC<AddAppConfigModalProps> = ({ 
  isOpen, 
  onClose, 
  onError, 
  onSuccess,
  editingConfig 
}) => {
  const [config, setConfig] = useState<DittoAppConfig>(createNewDittoAppConfig());
  const { saveAppConfig, isLoading: saving, error } = useAppConfig();

  // Initialize form with editing config or new config
  useEffect(() => {
    if (editingConfig) {
      setConfig(editingConfig);
    } else {
      setConfig(createNewDittoAppConfig());
    }
  }, [editingConfig, isOpen]);

  if (!isOpen) return null;

  const handleInputChange = (field: keyof DittoAppConfig, value: string | boolean) => {
    setConfig(prev => ({
      ...prev,
      [field]: value
    }));
  };

  const handleModeChange = (mode: 'online' | 'offline') => {
    setConfig(prev => ({
      ...prev,
      mode
    }));
  };

  const handleSave = async () => {
    // Basic validation
    if (!config.name.trim()) {
      onError('Name is required');
      return;
    }
    if (!config.appId.trim()) {
      onError('App ID is required');
      return;
    }

    if (config.mode === 'online') {
      if (!config.authToken.trim()) {
        onError('Auth Token is required for online mode');
        return;
      }
      if (!config.authUrl.trim()) {
        onError('Auth URL is required for online mode');
        return;
      }
    }

    // Use hook to save the configuration (works for both add and edit)
    const success = await saveAppConfig(config);
    
    if (success) {
      onClose();
      // Reset form
      setConfig(createNewDittoAppConfig());
      onSuccess?.();
    } else if (error) {
      onError(error);
    }
  };

  const handleCancel = () => {
    setConfig(createNewDittoAppConfig());
    onClose();
  };

  return (
    <div className="modal-overlay">
      <div className="modal-container">
        <div className="modal-header">
          <h2 className="modal-title">
            {editingConfig ? 'Edit Ditto App Config' : 'Add Ditto App Config'}
          </h2>
        </div>

        <div className="modal-content">
          {/* Mode Selection */}
          <div className="form-section">
            <label className="form-label">Mode</label>
            <div className="mode-selector">
              <button
                type="button"
                className={`mode-button ${config.mode === 'online' ? 'active' : ''}`}
                onClick={() => handleModeChange('online')}
              >
                Online Playground
              </button>
              <button
                type="button"
                className={`mode-button ${config.mode === 'offline' ? 'active' : ''}`}
                onClick={() => handleModeChange('offline')}
              >
                Offline
              </button>
            </div>
          </div>

          {/* Basic Information */}
          <div className="form-section">
            <h3 className="section-title">Basic Information</h3>
            <div className="form-group">
              <label className="form-label">Name</label>
              <input
                type="text"
                className="form-input"
                value={config.name}
                onChange={(e) => handleInputChange('name', e.target.value)}
                placeholder="Enter app name"
              />
            </div>
          </div>

          {/* Authorization Information */}
          <div className="form-section">
            <h3 className="section-title">Authorization Information</h3>
            <div className="form-group">
              <label className="form-label">AppID</label>
              <input
                type="text"
                className="form-input"
                value={config.appId}
                onChange={(e) => handleInputChange('appId', e.target.value)}
                placeholder="Enter App ID"
              />
            </div>
            <div className="form-group">
              <label className="form-label">Playground Token</label>
              <input
                type="text"
                className="form-input"
                value={config.authToken}
                onChange={(e) => handleInputChange('authToken', e.target.value)}
                placeholder="Enter auth token"
              />
            </div>
          </div>

          {/* Online Mode Fields */}
          {config.mode === 'online' && (
            <>
              {/* Ditto Server Information */}
              <div className="form-section">
                <h3 className="section-title">Ditto Server (BigPeer) Information</h3>
                <div className="form-group">
                  <label className="form-label">Auth URL</label>
                  <input
                    type="text"
                    className="form-input"
                    value={config.authUrl}
                    onChange={(e) => handleInputChange('authUrl', e.target.value)}
                    placeholder="Enter auth URL"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Websocket URL - Optional</label>
                  <input
                    type="text"
                    className="form-input"
                    value={config.websocketUrl}
                    onChange={(e) => handleInputChange('websocketUrl', e.target.value)}
                    placeholder="Enter websocket URL (optional)"
                  />
                </div>
              </div>

              {/* HTTP API - Optional */}
              <div className="form-section">
                <h3 className="section-title">Ditto Server - HTTP API - Optional</h3>
                <div className="form-group">
                  <label className="form-label">HTTP API URL</label>
                  <textarea
                    className="form-textarea"
                    value={config.httpApiUrl}
                    onChange={(e) => handleInputChange('httpApiUrl', e.target.value)}
                    placeholder="Enter HTTP API URL"
                    rows={3}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">HTTP API Key</label>
                  <textarea
                    className="form-textarea"
                    value={config.httpApiKey}
                    onChange={(e) => handleInputChange('httpApiKey', e.target.value)}
                    placeholder="Enter HTTP API Key"
                    rows={3}
                  />
                </div>
              </div>

              {/* Allow Untrusted Certificates */}
              <div className="form-section">
                <div className="checkbox-group">
                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={config.allowUntrustedCerts}
                      onChange={(e) => handleInputChange('allowUntrustedCerts', e.target.checked)}
                    />
                    <span className="checkbox-text">Allow untrusted certificates</span>
                  </label>
                  <p className="checkbox-description">
                    By allowing untrusted certificates, you are bypassing SSL certificate validation entirely,
                    which poses significant security risks. This setting should only be used in development
                    environments and never in production.
                  </p>
                </div>
              </div>

              {/* MongoDB Connection String */}
              <div className="form-section">
                <h3 className="section-title">MongoDB Driver Connection String - Optional</h3>
                <div className="form-group">
                  <label className="form-label">Connection String</label>
                  <textarea
                    className="form-textarea"
                    value={config.mongoDbConnectionString}
                    onChange={(e) => handleInputChange('mongoDbConnectionString', e.target.value)}
                    placeholder="Enter MongoDB connection string"
                    rows={4}
                  />
                </div>
              </div>
            </>
          )}
        </div>

        {/* Modal Footer */}
        <div className="modal-footer">
          <button
            type="button"
            className="button button-secondary"
            onClick={handleCancel}
            disabled={saving}
          >
            <X size={16} />
            Cancel
          </button>
          <button
            type="button"
            className="button button-primary"
            onClick={handleSave}
            disabled={saving}
          >
            {saving ? 'Saving...' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default AddAppConfigModal;