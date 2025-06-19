#!/bin/bash

# Script to export Developer ID certificate for GitHub Actions
# This script helps you export your Developer ID Application certificate
# and convert it to base64 for use in GitHub secrets

set -e

echo "🔐 Developer ID Certificate Export Script"
echo "=========================================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script must be run on macOS"
    exit 1
fi

# Check if security command is available
if ! command -v security &> /dev/null; then
    echo "❌ 'security' command not found. This script requires macOS."
    exit 1
fi

echo "📋 This script will help you export your Developer ID Application certificate"
echo "   for use with GitHub Actions."
echo ""

# Function to list available certificates
list_certificates() {
    echo "🔍 Available Developer ID Application certificates:"
    echo ""
    security find-identity -v -p codesigning | grep "Developer ID Application" || {
        echo "❌ No Developer ID Application certificates found."
        echo "   Please obtain a Developer ID Application certificate from Apple Developer."
        exit 1
    }
    echo ""
}

# Function to export certificate
export_certificate() {
    local cert_name="$1"
    local output_dir="$2"
    local password="$3"
    
    echo "📤 Exporting certificate: $cert_name"
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Export the certificate
    security export -k login.keychain -t identities -f pkcs12 -o "$output_dir/certificate.p12" "$cert_name" -P "$password"
    
    if [ $? -eq 0 ]; then
        echo "✅ Certificate exported successfully to: $output_dir/certificate.p12"
    else
        echo "❌ Failed to export certificate"
        exit 1
    fi
}

# Function to convert to base64
convert_to_base64() {
    local cert_file="$1"
    local output_file="$2"
    
    echo "🔄 Converting certificate to base64..."
    
    base64 -i "$cert_file" > "$output_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ Certificate converted to base64: $output_file"
        echo ""
        echo "📋 Next steps:"
        echo "1. Copy the contents of $output_file"
        echo "2. Add it as the MACOS_P12_BASE64 secret in your GitHub repository"
        echo "3. Add the password you used as the MACOS_P12_PASSWORD secret"
        echo ""
        echo "💡 You can copy the base64 content with: cat $output_file | pbcopy"
    else
        echo "❌ Failed to convert certificate to base64"
        exit 1
    fi
}

# Main script logic
echo "Step 1: Listing available certificates..."
list_certificates

echo "Step 2: Certificate export"
echo "=========================="
echo ""

# Get certificate name
read -p "Enter the full certificate name (or press Enter to use the first one): " cert_name

if [ -z "$cert_name" ]; then
    cert_name=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | sed 's/.*"\(.*\)".*/\1/')
    echo "Using certificate: $cert_name"
fi

# Get output directory
read -p "Enter output directory (default: ./certificates): " output_dir
output_dir=${output_dir:-./certificates}

# Get password
read -s -p "Enter password for the exported certificate: " password
echo ""
read -s -p "Confirm password: " password_confirm
echo ""

if [ "$password" != "$password_confirm" ]; then
    echo "❌ Passwords don't match"
    exit 1
fi

# Export certificate
export_certificate "$cert_name" "$output_dir" "$password"

# Convert to base64
convert_to_base64 "$output_dir/certificate.p12" "$output_dir/certificate_base64.txt"

echo "🎉 Certificate export complete!"
echo ""
echo "📁 Files created:"
echo "   - $output_dir/certificate.p12 (original certificate)"
echo "   - $output_dir/certificate_base64.txt (base64 encoded)"
echo ""
echo "🔒 Remember to:"
echo "   - Keep the certificate files secure"
echo "   - Add the base64 content to GitHub secrets"
echo "   - Store the password securely" 