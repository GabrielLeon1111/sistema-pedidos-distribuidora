; =================================================================
;  Instalador de Pedidos y Cobros (Distribuidora AM) para Windows
;  (Inno Setup 6). Se instala para el usuario (no pide permiso de
;  administrador), crea accesos directos en el escritorio y en el menú
;  Inicio, y se puede desinstalar desde "Agregar o quitar programas".
;
;  Compilar (después de `flutter build windows --release --dart-define-from-file=.env`):
;    ISCC.exe /DVersion=27 /DSalida=C:\Users\<usuario>\Downloads windows\installer\pedidos_y_cobros.iss
; =================================================================

#ifndef Version
  #define Version "1"
#endif
#ifndef Salida
  #define Salida "..\..\build\installer"
#endif
#define Release "..\..\build\windows\x64\runner\Release"
; Sysnative: la carpeta System32 de 64 bits vista desde el compilador (que es de 32 bits).
#define Sistema GetEnv("WINDIR") + "\Sysnative"

[Setup]
; Mismo AppId siempre: las versiones nuevas se instalan encima de la anterior.
AppId={{7C2E5A91-3D4B-4F8E-A1C6-9B0D2E4F6A83}
AppName=Pedidos y Cobros
AppVersion={#Version}
AppVerName=Pedidos y Cobros v{#Version}
AppPublisher=Distribuidora AM
DefaultDirName={localappdata}\Programs\Pedidos y Cobros
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#Salida}
OutputBaseFilename=PedidosYCobros.V{#Version}-Instalador
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sistema_pedidos.exe
UninstallDisplayName=Pedidos y Cobros - Distribuidora AM
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Librerías de Visual C++ (para que abra en cualquier Windows sin instalar nada más).
Source: "{#Sistema}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Sistema}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Sistema}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Pedidos y Cobros"; Filename: "{app}\sistema_pedidos.exe"
Name: "{autodesktop}\Pedidos y Cobros"; Filename: "{app}\sistema_pedidos.exe"; Tasks: escritorio

[Run]
Filename: "{app}\sistema_pedidos.exe"; Description: "Abrir Pedidos y Cobros"; Flags: nowait postinstall skipifsilent
