; KD Download Manager Windows kurulumu (Inno Setup 6). Windows\scripts\package.ps1 derler:
;
;   ISCC.exe /DVersion=1.9.4 /DArch=x64 /DAppDir=<yayımlanan klasör> /DOutputDir=<çıktı> KDDownloadManager.iss
;   → KDDownloadManager-Windows-x64-1.9.4-Setup.exe
;
; Kullanıcı başına kurulur, yönetici izni istemez: %LOCALAPPDATA%\Programs\KD Download Manager. Başlat menüsü ve
; isteğe bağlı masaüstü kısayolu, Uygulamalar listesinde kaldırma kaydı. Kurulum ve kaldırma önce açık olan uygulamayı
; kapatır: yeni sürümler "Local\KDDownloadManager-Quit-<kullanıcı>" olayını dinleyip indirmeleri kaydederek kapanır
; (App.QuitSignal); bu olayı bilmeyen eski sürümler (1.9.3 ve öncesi zip'ler) taskkill ile kapatılır.
;
; Uygulama içi güncelleme (Support\AppUpdater.cs) imzası doğrulanmış kurulumu şöyle çalıştırır:
;   Setup.exe /SILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /SP- /DIR="<uygulamanın klasörü>" /RELAUNCH=1 /LANG=tr
; /DIR, zip'ten kurulmuş bir kopyayı yerinde kurulu hale getirir; /RELAUNCH=1 bitince (başarısız olsa da) uygulamayı açar.

#ifndef Version
  #error "Version tanımlı değil (/DVersion=1.9.4)"
#endif
#ifndef Arch
  #error "Arch tanımlı değil (/DArch=x64 ya da arm64)"
#endif
#ifndef AppDir
  #error "AppDir tanımlı değil (dotnet publish çıktısı: KDDownloadManager.exe'nin klasörü)"
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName "KD Download Manager"
#define AppExe "KDDownloadManager.exe"

#if Arch == "arm64"
  #define Architectures "arm64"
#elif Arch == "x64"
  ; x64 sürümü ARM64 Windows 11'de de (öykünmeyle) çalışır.
  #define Architectures "x64compatible"
#else
  #error "Arch x64 ya da arm64 olmalı"
#endif

[Setup]
AppId={{F5B5747B-CA1F-4434-BB78-67F98E8050E2}
AppName={#AppName}
AppVersion={#Version}
AppVerName={#AppName} {#Version}
AppPublisher=Kadir Gül
AppPublisherURL=https://kddownloadmanager.com
AppSupportURL=https://github.com/kadirgl/KDDownloadManager/issues
AppUpdatesURL=https://github.com/kadirgl/KDDownloadManager/releases
VersionInfoVersion={#Version}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed={#Architectures}
ArchitecturesInstallIn64BitMode={#Architectures}
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=KDDownloadManager-Windows-{#Arch}-{#Version}-Setup
SetupIconFile=..\KDDownloadManager\Assets\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
ShowLanguageDialog=auto
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4
; Uygulama [Code]'da kapatılıyor; dosyası hâlâ kullanılan bir şey kalırsa Yeniden Başlatma Yöneticisi devreye girer.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[CustomMessages]
en.ClosingApp=Closing KD Download Manager…
tr.ClosingApp=KD Download Manager kapatılıyor…
en.RemoveData=Also delete KD Download Manager's settings, download list and history?%n%nThe files you downloaded are not deleted.
tr.RemoveData=KD Download Manager'ın ayarları, indirme listesi ve geçmişi de silinsin mi?%n%nİndirdiğiniz dosyalar silinmez.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Paketin kendi klasörleri her sürümde baştan kurulur (eski sürümden kalan araç ya da eklenti dosyası olmasın).
Type: filesandordirs; Name: "{app}\tools"
Type: filesandordirs; Name: "{app}\BrowserExtension"
Type: filesandordirs; Name: "{app}\Strings"

[Files]
Source: "{#AppDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Uygulama içi güncellemeden sonra yeni sürümü aç.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: RelaunchRequested

[UninstallDelete]
Type: filesandordirs; Name: "{app}\tools"
Type: dirifempty; Name: "{app}"

[Code]
const
  SYNCHRONIZE = $00100000;
  EVENT_MODIFY_STATE = $0002;

var
  Installed: Boolean;

function OpenEvent(DesiredAccess: Cardinal; InheritHandle: Boolean; Name: String): THandle;
  external 'OpenEventW@kernel32.dll stdcall';
function SetEvent(Event: THandle): Boolean;
  external 'SetEvent@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function QuitEventName: String;
begin
  Result := 'Local\KDDownloadManager-Quit-' + GetUserNameString;
end;

{ Asks a running copy to quit (it saves its downloads first) and waits; then ends any copy still running, e.g. an
  older version that does not know the quit event, or a copy started from a zip in another folder (only one copy
  runs per user, so it would keep the new one from starting). }
procedure CloseRunningApp;
var
  Event: THandle;
  I, Code: Integer;
begin
  Event := OpenEvent(EVENT_MODIFY_STATE or SYNCHRONIZE, False, QuitEventName);
  if Event <> 0 then
  begin
    SetEvent(Event);
    CloseHandle(Event);
    { The event goes away when the app's process ends. }
    for I := 1 to 150 do
    begin
      Sleep(200);
      Event := OpenEvent(SYNCHRONIZE, False, QuitEventName);
      if Event = 0 then Break;
      CloseHandle(Event);
    end;
  end;
  { The helper programs (aria2c, yt-dlp, ffmpeg) run in a job that ends with the app. No /T: the in-app update's
    setup is the app's child and must survive. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(500);
end;

function RelaunchRequested: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  WizardForm.PreparingLabel.Caption := CustomMessage('ClosingApp');
  CloseRunningApp;
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then Installed := True;
end;

{ An in-app update that did not go through (closed app, full disk) still reopens the app that is there. }
procedure DeinitializeSetup;
var
  Exe: String;
  Code: Integer;
begin
  if Installed or not RelaunchRequested then Exit;
  try
    Exe := ExpandConstant('{app}\{#AppExe}');
  except
    Exe := '';
  end;
  if (Exe <> '') and FileExists(Exe) then
    Exec(Exe, '', ExtractFileDir(Exe), SW_SHOWNORMAL, ewNoWait, Code);
end;

function PointsHere(Root: Integer; Key, Name: String): Boolean;
var
  Value: String;
begin
  Result := RegQueryStringValue(Root, Key, Name, Value)
    and (Pos(Lowercase(ExpandConstant('{app}\{#AppExe}')), Lowercase(Value)) > 0);
end;

{ Closes the app, then undoes what it registered for itself (Settings › Startup and Settings › Torrent), only while
  that points at this copy. Settings and the download list are kept unless the user asks to delete them. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Value: String;
begin
  { Once the user has confirmed, before any file is removed. }
  if CurUninstallStep = usUninstall then CloseRunningApp;
  if CurUninstallStep <> usPostUninstall then Exit;
  if PointsHere(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#AppName}') then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#AppName}');
  if PointsHere(HKCU, 'Software\Classes\magnet\shell\open\command', '') then
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\magnet');
  if PointsHere(HKCU, 'Software\Classes\KDDownloadManager.Torrent\shell\open\command', '') then
  begin
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\KDDownloadManager.Torrent');
    if RegQueryStringValue(HKCU, 'Software\Classes\.torrent', '', Value) and (Value = 'KDDownloadManager.Torrent') then
      RegDeleteValue(HKCU, 'Software\Classes\.torrent', '');
    RegDeleteValue(HKCU, 'Software\Classes\.torrent\OpenWithProgids', 'KDDownloadManager.Torrent');
    RegDeleteKeyIfEmpty(HKCU, 'Software\Classes\.torrent\OpenWithProgids');
    RegDeleteKeyIfEmpty(HKCU, 'Software\Classes\.torrent');
  end;
  if not UninstallSilent and
     (MsgBox(CustomMessage('RemoveData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    DelTree(ExpandConstant('{localappdata}\KDDownloadManager'), True, True, True);
end;
