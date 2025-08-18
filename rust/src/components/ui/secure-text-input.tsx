import React, { useState } from 'react';
import { Eye, EyeOff, Copy } from 'lucide-react';

interface SecureTextInputProps {
  value: string;
  label?: string;
  className?: string;
  onCopy?: () => void;
  copyTooltip?: string;
}

const SecureTextInput: React.FC<SecureTextInputProps> = ({ 
  value, 
  label,
  className = "",
  onCopy,
  copyTooltip = "Copy to clipboard"
}) => {
  const [isVisible, setIsVisible] = useState(false);

  const generateMaskedText = (text: string): string => {
    if (!text) return "";
    // Generate a random number of stars between 20-40 to obscure the actual length
    const starCount = Math.floor(Math.random() * 21) + 20;
    return "•".repeat(starCount);
  };

  const toggleVisibility = () => {
    setIsVisible(!isVisible);
  };

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      onCopy?.();
    } catch (err) {
      console.error('Failed to copy text: ', err);
    }
  };

  return (
    <div className={`flex flex-col ${className}`}>
      {label && (
        <label className="text-sm font-medium text-slate-300 mb-1">
          {label}
        </label>
      )}
      <div className="relative flex items-center">
        <div 
          className="flex-1 bg-slate-800 border border-slate-600 rounded px-3 py-2 text-sm font-mono text-slate-100 cursor-pointer hover:bg-slate-750 transition-colors"
          onClick={toggleVisibility}
        >
          {isVisible ? value : generateMaskedText(value)}
        </div>
        <div className="flex ml-2 gap-1">
          <button
            onClick={toggleVisibility}
            className="p-2 text-slate-400 hover:text-slate-200 transition-colors"
            title={isVisible ? "Hide" : "Show"}
          >
            {isVisible ? (
              <EyeOff className="w-4 h-4" />
            ) : (
              <Eye className="w-4 h-4" />
            )}
          </button>
          <button
            onClick={handleCopy}
            className="p-2 text-slate-400 hover:text-slate-200 transition-colors"
            title={copyTooltip}
          >
            <Copy className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};

export default SecureTextInput;