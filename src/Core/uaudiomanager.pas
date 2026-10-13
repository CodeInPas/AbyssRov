unit uAudioManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Dialogs, BASS; // Pastikan Anda memiliki bass.pas di folder project

type
  { Enum untuk berbagai jenis efek suara }
  TSoundEffect = (
    sfxSonarPing,
    sfxLeviathanAggro,
    sfxGlitch,
    sfxEMP,
    sfxDecoy,
    sfxExtract,
    sfxAlarm
  );

  TAudioManager = class
  private
    FInitialized: Boolean;
    FAudioPath: String;

    // BGM & Looping Streams
    FStreamAmbient: HSTREAM;
    FStreamThruster: HSTREAM;

    // Sound Effects (Samples)
    FSampSonar: HSAMPLE;
    FSampLeviathan: HSAMPLE;
    FSampGlitch: HSAMPLE;
    FSampEMP: HSAMPLE;
    FSampDecoy: HSAMPLE;
    FSampExtract: HSAMPLE;
    FSampAlarm: HSAMPLE;

    function LoadSample(const FileName: String; MaxSimultaneous: Integer = 3): HSAMPLE;
    function LoadStream(const FileName: String; IsLooping: Boolean): HSTREAM;
  public
    constructor Create;
    destructor Destroy; override;

    procedure PlayAmbient(Enable: Boolean);
    procedure UpdateThrusterVolume(ThrustValue: Single);
    procedure PlaySFX(SFX: TSoundEffect);
    procedure StopAll;
  end;

var
  AudioManager: TAudioManager;

implementation

{ TAudioManager }

constructor TAudioManager.Create;
begin
  inherited Create;
  FInitialized := False;
  FAudioPath := ExtractFilePath(Application.ExeName) + 'data\audio\';
  ForceDirectories(FAudioPath);

  // Inisialisasi BASS Engine (Default Device, 44100hz, Stereo)
  if not BASS_Init(-1, 44100, 0, 0, nil) then
  begin
    // Jika gagal (misal bass.dll tidak ada), jangan crash, cukup disable audio
    Exit;
  end;

  FInitialized := True;

  // Load Ambient & Thruster sebagai Stream (Cocok untuk file durasi panjang/looping)
  FStreamAmbient := LoadStream('ambient_deepsea.mp3', True);
  FStreamThruster := LoadStream('thruster_loop.mp3', True);

  // Set volume awal thruster ke 0 (karena mesin belum dipacu)
  if FStreamThruster <> 0 then
  begin
    BASS_ChannelSetAttribute(FStreamThruster, BASS_ATTRIB_VOL, 0.0);
    BASS_ChannelPlay(FStreamThruster, False);
  end;

  // Load SFX sebagai Sample (Cocok untuk suara pendek yang bisa tumpang tindih)
  FSampSonar := LoadSample('sonar_ping.mp3', 2);
  FSampLeviathan := LoadSample('leviathan_roar.mp3', 1);
  FSampGlitch := LoadSample('ui_glitch.mp3', 3);
  FSampEMP := LoadSample('emp_blast.mp3', 1);
  FSampDecoy := LoadSample('decoy_pulse.mp3', 1);
  FSampExtract := LoadSample('drill_extract.mp3', 1);
  FSampAlarm := LoadSample('alarm_warning.mp3', 2);
end;

destructor TAudioManager.Destroy;
begin
  if FInitialized then
  begin
    StopAll;

    // Free Samples
    if FSampSonar <> 0 then BASS_SampleFree(FSampSonar);
    if FSampLeviathan <> 0 then BASS_SampleFree(FSampLeviathan);
    if FSampGlitch <> 0 then BASS_SampleFree(FSampGlitch);
    if FSampEMP <> 0 then BASS_SampleFree(FSampEMP);
    if FSampDecoy <> 0 then BASS_SampleFree(FSampDecoy);
    if FSampExtract <> 0 then BASS_SampleFree(FSampExtract);
    if FSampAlarm <> 0 then BASS_SampleFree(FSampAlarm);

    // Free Streams
    if FStreamAmbient <> 0 then BASS_StreamFree(FStreamAmbient);
    if FStreamThruster <> 0 then BASS_StreamFree(FStreamThruster);

    // Tutup engine BASS
    BASS_Free();
  end;
  inherited Destroy;
end;

function TAudioManager.LoadSample(const FileName: String; MaxSimultaneous: Integer): HSAMPLE;
var
  FullPath: String;
begin
  Result := 0;
  if not FInitialized then Exit;

  FullPath := FAudioPath + FileName;
  if FileExists(FullPath) then
    Result := BASS_SampleLoad(False, PChar(FullPath), 0, 0, MaxSimultaneous, 0);
end;

function TAudioManager.LoadStream(const FileName: String; IsLooping: Boolean): HSTREAM;
var
  FullPath: String;
  Flags: DWORD;
begin
  Result := 0;
  if not FInitialized then Exit;

  FullPath := FAudioPath + FileName;
  if FileExists(FullPath) then
  begin
    Flags := 0;
    if IsLooping then Flags := BASS_SAMPLE_LOOP;
    Result := BASS_StreamCreateFile(False, PChar(FullPath), 0, 0, Flags);
  end;
end;

procedure TAudioManager.PlayAmbient(Enable: Boolean);
begin
  if (not FInitialized) or (FStreamAmbient = 0) then Exit;

  if Enable then
    BASS_ChannelPlay(FStreamAmbient, False)
  else
    BASS_ChannelPause(FStreamAmbient);
end;

procedure TAudioManager.UpdateThrusterVolume(ThrustValue: Single);
var
  TargetVol: Single;
begin
  if (not FInitialized) or (FStreamThruster = 0) then Exit;

  // Normalisasi nilai thrust (0..100) menjadi skala volume (0.0 .. 1.0)
  TargetVol := Abs(ThrustValue) / 100.0;

  // Batasi volume mesin maksimal di 60% agar tidak menutupi suara game lainnya
  if TargetVol > 0.6 then TargetVol := 0.6;

  BASS_ChannelSetAttribute(FStreamThruster, BASS_ATTRIB_VOL, TargetVol);
end;

procedure TAudioManager.PlaySFX(SFX: TSoundEffect);
var
  Samp: HSAMPLE;
  Chan: HCHANNEL;
begin
  if not FInitialized then Exit;

  Samp := 0;
  case SFX of
    sfxSonarPing: Samp := FSampSonar;
    sfxLeviathanAggro: Samp := FSampLeviathan;
    sfxGlitch: Samp := FSampGlitch;
    sfxEMP: Samp := FSampEMP;
    sfxDecoy: Samp := FSampDecoy;
    sfxExtract: Samp := FSampExtract;
    sfxAlarm: Samp := FSampAlarm;
  end;

  if Samp <> 0 then
  begin
    // Dapatkan channel dari sample untuk memutarnya
    Chan := BASS_SampleGetChannel(Samp, False);
    if Chan <> 0 then
      BASS_ChannelPlay(Chan, False);
  end;
end;

procedure TAudioManager.StopAll;
begin
  if not FInitialized then Exit;

  // Menghentikan semua output audio secara instan
  BASS_Pause();
  // Catatan: Gunakan BASS_Start() jika ingin meresume setelah StopAll
end;

end.
