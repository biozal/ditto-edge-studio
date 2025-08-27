export interface DittoAppConfig {
  _id: string;
  name: string;
  appId: string;
  authToken: string;
  authUrl: string;
  websocketUrl: string;
  httpApiUrl: string;
  httpApiKey: string;
  mongoDbConnectionString: string;
  mode: 'online' | 'offline';
  allowUntrustedCerts: boolean;
}

export function createNewDittoAppConfig(): DittoAppConfig {
  return {
    _id: crypto.randomUUID(),
    name: '',
    appId: '',
    authToken: '',
    authUrl: '',
    websocketUrl: '',
    httpApiUrl: '',
    httpApiKey: '',
    mongoDbConnectionString: '',
    mode: 'online',
    allowUntrustedCerts: false,
  };
}