import React, { useState, useEffect, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { save } from '@tauri-apps/plugin-dialog';
import { writeTextFile } from '@tauri-apps/plugin-fs';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { RefreshCw, Trash2, Download, AlertCircle, AlertTriangle, Info, Bug, Search } from 'lucide-react';

interface LogEntry {
  timestamp: string;
  level: 'Error' | 'Warn' | 'Info' | 'Debug' | 'Trace';
  target: string;
  message: string;
}

const LogsWindow: React.FC = () => {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [logCount, setLogCount] = useState(0);
  const logsEndRef = useRef<HTMLDivElement>(null);

  const loadLogs = async () => {
    try {
      setLoading(true);
      const [logsData, count] = await Promise.all([
        invoke<LogEntry[]>('get_logs'),
        invoke<number>('get_log_count')
      ]);
      setLogs(logsData);
      setLogCount(count);
    } catch (error) {
      console.error('Failed to load logs:', error);
    } finally {
      setLoading(false);
    }
  };

  const clearLogs = async () => {
    try {
      await invoke('clear_logs');
      await loadLogs();
    } catch (error) {
      console.error('Failed to clear logs:', error);
    }
  };

  const saveLogsToFile = async () => {
    try {
      const logsString = await invoke<string>('get_logs_as_string');
      
      const filePath = await save({
        defaultPath: `ditto-edge-studio-logs-${new Date().toISOString().split('T')[0]}.txt`,
        filters: [
          {
            name: 'Text Files',
            extensions: ['txt']
          },
          {
            name: 'All Files',
            extensions: ['*']
          }
        ]
      });

      if (filePath) {
        await writeTextFile(filePath, logsString);
        console.log('Logs saved to:', filePath);
      }
    } catch (error) {
      console.error('Failed to save logs:', error);
    }
  };

  const scrollToBottom = () => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    loadLogs();
    // Auto-refresh logs every 2 seconds
    const interval = setInterval(loadLogs, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [logs]);

  const getLogLevelBadgeStyle = (level: string) => {
    switch (level) {
      case 'Error': return { backgroundColor: '#dc2626', color: 'white' }; // red-600
      case 'Warn': return { backgroundColor: '#f59e0b', color: 'white' }; // amber-500
      case 'Info': return { backgroundColor: '#059669', color: 'white' }; // emerald-600
      case 'Debug': return { backgroundColor: '#7c3aed', color: 'white' }; // violet-600
      case 'Trace': return { backgroundColor: '#64748b', color: 'white' }; // slate-500
      default: return { backgroundColor: '#059669', color: 'white' };
    }
  };

  const getLogLevelIcon = (level: string) => {
    switch (level) {
      case 'Error': return <AlertCircle className="w-3 h-3" />;
      case 'Warn': return <AlertTriangle className="w-3 h-3" />;
      case 'Info': return <Info className="w-3 h-3" />;
      case 'Debug': return <Bug className="w-3 h-3" />;
      case 'Trace': return <Search className="w-3 h-3" />;
      default: return <Info className="w-3 h-3" />;
    }
  };

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: '#171717' }}>
      {/* Header */}
      <div style={{ backgroundColor: '#262626', borderBottom: '1px solid #404040' }}>
        <div className="px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-semibold text-slate-100">Application Logs</h1>
              <p className="text-sm text-slate-400 mt-1">
                {logCount} {logCount === 1 ? 'entry' : 'entries'}
              </p>
            </div>
            <div className="flex gap-3">
              <Button 
                onClick={loadLogs} 
                disabled={loading}
                className="bg-slate-700 hover:bg-slate-600 text-slate-100 border-slate-600"
                size="sm"
              >
                <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
                {loading ? 'Loading...' : 'Refresh'}
              </Button>
              <Button 
                onClick={clearLogs}
                className="bg-red-600 hover:bg-red-700 text-white"
                size="sm"
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Clear Logs
              </Button>
              <Button 
                onClick={saveLogsToFile}
                className="bg-blue-600 hover:bg-blue-700 text-white"
                size="sm"
              >
                <Download className="w-4 h-4 mr-2" />
                Save to File
              </Button>
            </div>
          </div>
        </div>
      </div>

      {/* Logs Content */}
      <div className="flex-1 overflow-hidden">
        {loading && logs.length === 0 ? (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
            <div style={{ textAlign: 'center' }}>
              <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-4" style={{ color: '#a1a1aa' }} />
              <p style={{ color: '#a1a1aa' }}>Loading logs...</p>
            </div>
          </div>
        ) : logs.length === 0 ? (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
            <div style={{ textAlign: 'center' }}>
              <Info className="w-12 h-12 mx-auto mb-4" style={{ color: '#a1a1aa' }} />
              <h3 style={{ fontSize: '18px', fontWeight: '600', marginBottom: '8px', color: '#f4f4f5' }}>No logs available</h3>
              <p style={{ fontSize: '14px', color: '#a1a1aa' }}>
                Logs will appear here as the application runs
              </p>
            </div>
          </div>
        ) : (
          <ScrollArea className="h-full p-4">
            <div className="space-y-3">
              {logs.map((log, index) => (
                <div key={index} style={{ backgroundColor: '#262626', borderRadius: '8px', padding: '16px', border: '1px solid #404040', marginBottom: '12px' }}>
                  <div style={{ display: 'flex', alignItems: 'flex-start' }}>
                    <div 
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px',
                        fontSize: '10px',
                        fontWeight: '600',
                        padding: '3px 8px',
                        borderRadius: '4px',
                        marginRight: '24px',
                        flexShrink: 0,
                        ...getLogLevelBadgeStyle(log.level)
                      }}
                    >
                      {getLogLevelIcon(log.level)}
                      {log.level.toUpperCase()}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', marginBottom: '8px' }}>
                        <span style={{ 
                          fontSize: '12px', 
                          color: '#a1a1aa', 
                          fontFamily: 'monospace',
                          marginRight: '24px',
                          whiteSpace: 'nowrap'
                        }}>
                          {formatTimestamp(log.timestamp)}
                        </span>
                        <span style={{
                          fontSize: '12px',
                          backgroundColor: '#404040',
                          color: '#e4e4e7',
                          padding: '4px 12px',
                          borderRadius: '4px',
                          whiteSpace: 'nowrap'
                        }}>
                          {log.target}
                        </span>
                      </div>
                      <p style={{
                        fontSize: '14px',
                        fontFamily: 'monospace',
                        wordBreak: 'break-all',
                        color: '#f4f4f5',
                        lineHeight: '1.5'
                      }}>
                        {log.message}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
              <div ref={logsEndRef} />
            </div>
          </ScrollArea>
        )}
      </div>

      {/* Footer */}
      <div style={{ backgroundColor: '#262626', borderTop: '1px solid #404040', padding: '12px 24px' }}>
        <p style={{ fontSize: '12px', color: '#a1a1aa', textAlign: 'center' }}>
          Press <kbd style={{ padding: '4px 8px', backgroundColor: '#404040', color: '#e4e4e7', borderRadius: '4px', fontSize: '12px', fontFamily: 'monospace' }}>Cmd+L</kbd> in the main window to toggle this logs window
        </p>
      </div>
    </div>
  );
};

export default LogsWindow;