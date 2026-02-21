# App Release Setup Guide

This guide explains how to set up automated releases for Edge Debug Helper SwiftUI Application.

# MacOS 

## Overview

This app uses XCode Cloud to build the app. These directions walk you through the process of creating a release.

## Prerequisites

### 1. Apple Developer Account
You need access to the Apple Developer account. Once you have access, you must log into Xcode with this so that you can see the XCode Cloud setup.  

## Setup

Any code merged into the `main` branch in the SwiftUI folder will auto trigger a release build in XCode Cloud.  You should always make sure you bump the version number in the `Info.plist` file prior to merging.  Once the build is completed, you can log into App Store Connect and download the build.  Save the zip file to the `build` folder and unzip it.

Once unzipped, you can run the script `create-build.sh` in the `scripts` folder.  This will create a DMG file in the `build` folder.  You can then upload this to GitHub as a release asset. 






