import React from 'react';
import { Edit, Trash2 } from 'lucide-react';
import { DittoAppConfig } from '../models/DittoAppConfig';
import { Button } from './ui/button';
import SecureTextInput from './ui/secure-text-input';

interface AppCardProps {
  config: DittoAppConfig;
  onEdit: (config: DittoAppConfig) => void;
  onDelete: (configId: string) => void;
}

const AppCard: React.FC<AppCardProps> = ({ config, onEdit, onDelete }) => {
  const handleEdit = () => {
    onEdit(config);
  };

  const handleDelete = () => {
    onDelete(config._id);
  };

  const getAppIcon = (appName: string): string => {
    // Generate a simple avatar-style icon using the first letter
    return appName.charAt(0).toUpperCase();
  };

  const getAppIconColor = (appName: string): string => {
    // Generate a consistent color based on the app name
    const colors = [
      'bg-blue-600',
      'bg-green-600', 
      'bg-purple-600',
      'bg-red-600',
      'bg-yellow-600',
      'bg-indigo-600',
      'bg-pink-600',
      'bg-teal-600'
    ];
    
    let hash = 0;
    for (let i = 0; i < appName.length; i++) {
      hash = appName.charCodeAt(i) + ((hash << 5) - hash);
    }
    
    return colors[Math.abs(hash) % colors.length];
  };

  return (
    <div className="bg-slate-800 border border-slate-700 rounded-lg p-6 hover:border-slate-600 transition-colors">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-4">
          {/* App Icon */}
          <div className={`w-16 h-16 ${getAppIconColor(config.name)} rounded-lg flex items-center justify-center text-white text-xl font-bold`}>
            {getAppIcon(config.name)}
          </div>
          
          {/* App Name */}
          <div>
            <h3 className="text-lg font-semibold text-slate-100 mb-1">
              {config.name}
            </h3>
            <span className={`inline-block px-2 py-1 text-xs rounded-full ${
              config.mode === 'online' 
                ? 'bg-green-100 text-green-800' 
                : 'bg-gray-100 text-gray-800'
            }`}>
              {config.mode}
            </span>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex gap-2">
          <Button
            onClick={handleEdit}
            variant="outline"
            size="sm"
            className="bg-slate-700 border-slate-600 text-slate-200 hover:bg-slate-600"
          >
            <Edit className="w-4 h-4 mr-1" />
            Edit
          </Button>
          <Button
            onClick={handleDelete}
            variant="outline"
            size="sm"
            className="bg-red-700 border-red-600 text-red-200 hover:bg-red-600"
          >
            <Trash2 className="w-4 h-4 mr-1" />
            Delete
          </Button>
        </div>
      </div>

      {/* App Details */}
      <div className="space-y-3">
        <SecureTextInput
          label="App ID"
          value={config.appId}
          className="mb-3"
        />
        
        <SecureTextInput
          label="Auth Token"
          value={config.authToken}
          className="mb-3"
        />

        {/* Additional Info */}
        <div className="pt-3 border-t border-slate-700">
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span className="text-slate-400">Auth URL:</span>
              <p className="text-slate-200 truncate" title={config.authUrl}>
                {config.authUrl}
              </p>
            </div>
            {config.websocketUrl && (
              <div>
                <span className="text-slate-400">WebSocket:</span>
                <p className="text-slate-200 truncate" title={config.websocketUrl}>
                  {config.websocketUrl}
                </p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default AppCard;