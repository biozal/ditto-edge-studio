# dotnet build instructions

Use Parcel
https://docs.avaloniaui.net/tools/parcel/command-line-reference

Windows:
```sh
parcel step create-nsis ./signed ./installer.exe -p ./dotnet/src/EdgeStudio/EdgeStudio.csproj 
```

Linux zip:
```sh
parcel step create-zip ./publish ./archive.zip -p ./dotnet/src/EdgeStudio/EdgeStudio.csproj 
```

Linux deb:
```sh
parcel step create-deb ./publish ./installer.deb -p ./dotnet/src/EdgeStudio/EdgeStudio.csproj 
```
