; Musico Windows installer

#define AppName "Musico"
#define AppPublisher "Musico"
#define AppVersion "1.0.2"

[Setup]
AppId={{B9F0E3C8-7D9C-4B27-9EE8-8F6F8B5F2A11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Musico
DefaultGroupName=Musico
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Musico.exe
OutputDir=dist
OutputBaseFilename=Musico-Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Musico"; Filename: "{app}\Musico.exe"
Name: "{autodesktop}\Musico"; Filename: "{app}\Musico.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Musico.exe"; Description: "Launch Musico"; Flags: nowait postinstall skipifsilent

[Code]
var
  MediaDirPage: TInputDirWizardPage;

function EscapeJsonText(Value: String): String;
begin
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  Result := Value;
end;

procedure InitializeWizard;
begin
  MediaDirPage := CreateInputDirPage(
    wpSelectDir,
    'Media storage location',
    'Where should Musico store media?',
    'Choose a writable folder for imported music, videos, artwork, and downloads.',
    False,
    ''
  );
  MediaDirPage.Add('Musico media folder');
  MediaDirPage.Values[0] := ExpandConstant('{userdocs}\Musico');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  MediaRoot: String;
  Json: String;
begin
  if CurStep = ssPostInstall then
  begin
    MediaRoot := MediaDirPage.Values[0];
    if not DirExists(MediaRoot) then
      CreateDir(MediaRoot);

    Json := '{' +
      '"mediaRoot":"' + EscapeJsonText(MediaRoot) + '",' +
      '"setupCompleted":true' +
      '}';
    SaveStringToFile(
      ExpandConstant('{app}\musico_setup.json'),
      Json,
      False
    );
  end;
end;
