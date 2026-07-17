[Setup]
AppId={{C789B1F2-D5E7-45A0-A9BD-3392FFAD2201}}
AppName=SEDS Portal
AppVersion={#AppVersion}
AppPublisher=Kumaraguru SEDS
DefaultDirName={autopf}\SEDS Portal
DefaultGroupName=SEDS Portal
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=seds-portal-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\frontend_fluttter_app.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SEDS Portal"; Filename: "{app}\frontend_fluttter_app.exe"
Name: "{autodesktop}\SEDS Portal"; Filename: "{app}\frontend_fluttter_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\frontend_fluttter_app.exe"; Description: "{cm:LaunchProgram,SEDS Portal}"; Flags: nowait postinstall skipifsilent
