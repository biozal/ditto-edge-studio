import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import LogsWindow from "./components/LogsWindow";
import AppListing from "./components/AppListing";
import ErrorModal from "./components/ErrorModal";
import { useDitto } from "./providers/DittoProvider";
import "./App.css";

function App() {
  const [error, setError] = useState<string | null>(null);
  const { error: dittoError } = useDitto();

  async function openLogsWindow() {
    try {
      await invoke("open_logs_window");
    } catch (error) {
      console.error("Failed to open logs window:", error);
    }
  }

  // Keyboard shortcut handler for Cmd+L
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Cmd+L (Mac) or Ctrl+L (Windows/Linux)
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'l') {
        event.preventDefault();
        openLogsWindow();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, []);

  // Check if this is the logs window
  if ((window as any).__IS_LOGS_WINDOW__) {
    return <LogsWindow />;
  }

  // Handle Ditto initialization errors
  useEffect(() => {
    if (dittoError) {
      setError(dittoError);
    }
  }, [dittoError]);

  return (
    <div className="app-container">
      {/* Main content area with app listing */}
      <main className="app-main">
        <AppListing />
      </main>

      {/* Error Modal */}
      {error && (
        <ErrorModal
          error={error}
          onClose={() => setError(null)}
        />
      )}
    </div>
  );
}

export default App;
