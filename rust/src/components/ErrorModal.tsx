import React from 'react';
import { AlertTriangle, X } from 'lucide-react';

interface ErrorModalProps {
  error: string;
  onClose: () => void;
}

const ErrorModal: React.FC<ErrorModalProps> = ({ error, onClose }) => {
  return (
    <div className="modal-overlay">
      <div className="error-modal">
        <div className="error-header">
          <div className="error-icon">
            <AlertTriangle size={24} />
          </div>
          <h2 className="error-title">Error</h2>
          <button 
            className="error-close"
            onClick={onClose}
            title="Close"
          >
            <X size={20} />
          </button>
        </div>
        
        <div className="error-content">
          <p className="error-message">{error}</p>
        </div>
        
        <div className="error-footer">
          <button 
            className="button button-primary"
            onClick={onClose}
          >
            OK
          </button>
        </div>
      </div>
    </div>
  );
};

export default ErrorModal;